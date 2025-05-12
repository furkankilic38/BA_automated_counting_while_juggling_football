import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// NativeDetectionService - Schnittstelle zu nativen Erkennungsfunktionen
///
/// Diese Klasse stellt Flutter-Methoden bereit, um mit den nativen Java-Implementierungen
/// der Pose- und Ballerkennung zu kommunizieren. Sie verwaltet das Laden der ML-Modelle
/// und die Konvertierung der Kamerabilder für die ML-Verarbeitung.
class NativeDetectionService {
  // Methodenkanäle für die Kommunikation mit nativem Code
  static const MethodChannel _channel =
      MethodChannel('com.example.footy_testing/detection');
  static const MethodChannel _ballChannel =
      MethodChannel('com.example.footy_testing/ball_detection');

  // Status der Modellladung
  static bool _modelsLoaded = false;
  static bool _ballModelLoaded = false;

  /// Lädt die ML-Modelle für Pose- und Ballerkennung
  ///
  /// @param useGpu Gibt an, ob GPU-Beschleunigung verwendet werden soll
  /// @param retryCount Anzahl der Wiederholungsversuche bei Fehlern
  /// @return true wenn beide Modelle erfolgreich geladen wurden
  static Future<bool> loadModels(
      {bool useGpu = false, int retryCount = 1}) async {
    try {
      debugPrint('Lade Erkennungsmodelle, Versuche: $retryCount');

      // MoveNet (Pose-Erkennungsmodell) laden
      for (int i = 0; i < retryCount; i++) {
        try {
          debugPrint('MoveNet-Ladeversuch ${i + 1}/$retryCount');
          final result = await _channel.invokeMethod('loadModels', {
            'movenetModelPath': 'assets/movenet_lightning.tflite',
            'useGpu': useGpu,
          });

          _modelsLoaded = result == true;
          if (_modelsLoaded) break;
        } catch (e) {
          debugPrint(
              'Fehler beim Laden des MoveNet-Modells (Versuch ${i + 1}): $e');
          if (i == retryCount - 1) rethrow;
          await Future.delayed(Duration(milliseconds: 500));
        }
      }

      // YOLOv8 (Ballerkennungsmodell) laden
      for (int i = 0; i < retryCount; i++) {
        try {
          debugPrint(
              'YOLOv8-Ladeversuch für Ballerkennung ${i + 1}/$retryCount');
          final ballResult = await _ballChannel.invokeMethod('loadModels', {
            'modelPath': 'assets/yolov8n_int8.tflite',
            'labelsPath': 'assets/labels.txt',
            'useGpu': useGpu,
          });

          _ballModelLoaded = ballResult == true;
          if (_ballModelLoaded) break;
        } catch (e) {
          debugPrint(
              'Fehler beim Laden des YOLOv8-Modells (Versuch ${i + 1}): $e');
          if (i == retryCount - 1) rethrow;
          await Future.delayed(Duration(milliseconds: 500));
        }
      }

      final allModelsLoaded = _modelsLoaded && _ballModelLoaded;
      debugPrint(
          'Modell-Ladeergebnis: MoveNet=$_modelsLoaded, YOLOv8Ball=$_ballModelLoaded');
      return allModelsLoaded;
    } on PlatformException catch (e) {
      debugPrint('Fehler beim Laden der Modelle: ${e.message}');
      return false;
    }
  }

  /// Erkennt Objekte (primär Personen) im Kamerabild mit MoveNet
  ///
  /// @param image Das Kamerabild zur Analyse
  /// @param isFrontCamera Gibt an, ob die Frontkamera verwendet wird
  /// @return DetectionResult mit erkannten Personen und Keypoints
  static Future<DetectionResult> detectObjects(CameraImage image,
      {bool isFrontCamera = false}) async {
    // Stelle sicher, dass Modelle geladen sind
    if (!_modelsLoaded) {
      try {
        final loaded = await loadModels();
        if (!loaded) {
          debugPrint('Modelle konnten nicht geladen werden');
          return DetectionResult.empty();
        }
      } catch (e) {
        debugPrint('Unerwarteter Fehler beim Laden der Modelle: $e');
        return DetectionResult.empty();
      }
    }

    try {
      // Rotationsparameter je nach Plattform und Kamera
      int rotation = 0;
      if (Platform.isAndroid) {
        rotation = isFrontCamera ? 270 : 90;
      }
      debugPrint(
          'Kamera-Rotation: $rotation Grad, Frontkamera: $isFrontCamera');

      // Parameter für nativen Aufruf vorbereiten
      final Map<String, dynamic> arguments = {
        'imageBytes': image.planes[0].bytes,
        'width': image.width,
        'height': image.height,
        'rotation': rotation,
        'iouThreshold': 0.25,
        'confThreshold': 0.01,
        'isFrontCamera': isFrontCamera,
      };

      // YUV420-Daten hinzufügen, falls verfügbar (für bessere Farbkonvertierung)
      if (image.format.group == ImageFormatGroup.yuv420) {
        if (image.planes.length >= 3) {
          arguments['uPlane'] = image.planes[1].bytes;
          arguments['vPlane'] = image.planes[2].bytes;
          arguments['uvRowStride'] = image.planes[1].bytesPerRow;
          arguments['uvPixelStride'] = image.planes[1].bytesPerPixel ?? 1;
          debugPrint('YUV420-Format erkannt, sende alle Planes');
        }
      }

      // Native Posenerkennung aufrufen
      final Map<String, dynamic>? result =
          await _channel.invokeMapMethod('detectObjects', arguments);

      if (result == null) {
        return DetectionResult.empty();
      }

      return DetectionResult.fromMap(result);
    } on PlatformException catch (e) {
      debugPrint('Fehler bei der Objekterkennung: ${e.message}');
      return DetectionResult.empty();
    } catch (e) {
      debugPrint('Unerwarteter Fehler bei der Objekterkennung: $e');
      return DetectionResult.empty();
    }
  }

  /// Einfache Testmethode zur Überprüfung der nativen Anbindung
  static Future<String> testConnection() async {
    try {
      final String result = await _channel.invokeMethod('getTestString');
      return result;
    } on PlatformException catch (e) {
      return 'Fehler: ${e.message}';
    }
  }

  /// Testet die Ballerkennung mit einem Beispielbild (für Debugging)
  static Future<Map<String, dynamic>> testBallDetection() async {
    try {
      if (!_modelsLoaded) {
        final loaded = await loadModels();
        if (!loaded) {
          debugPrint('Models could not be loaded');
          return {'error': 'Models not loaded'};
        }
      }

      debugPrint('Testing soccer ball detection');

      final result = await _channel.invokeMapMethod('testBallDetection');

      if (result == null) {
        return {'error': 'No result from native code'};
      }

      final detections = (result['detections'] as List<dynamic>?)?.map((det) {
            return DetectedObject(
              tag: det['tag'],
              confidence: det['confidence'],
              box: (det['box'] as List<dynamic>)
                  .map((e) => e as double)
                  .toList(),
              keypoints: det['keypoints'] != null
                  ? (det['keypoints'] as List<dynamic>?)
                      ?.map((k) => Keypoint(
                            name: k['name'],
                            x: k['x'],
                            y: k['y'],
                            score: k['score'],
                          ))
                      .toList()
                  : null,
            );
          }).toList() ??
          [];

      final Uint8List? imageBytes = result['resultImage'] as Uint8List?;

      return {
        'detections': detections,
        'imageBytes': imageBytes,
      };
    } catch (e) {
      debugPrint('Error testing ball detection: $e');
      return {'error': e.toString()};
    }
  }

  /// Erkennt Fußbälle im Kamerabild mit YOLOv8
  ///
  /// @param image Das Kamerabild zur Analyse
  /// @param isFrontCamera Gibt an, ob die Frontkamera verwendet wird
  /// @return DetectionResult mit erkannten Bällen und Bounding-Boxen
  static Future<DetectionResult> detectBall(CameraImage image,
      {bool isFrontCamera = false}) async {
    // Stelle sicher, dass das Ballerkennungsmodell geladen ist
    if (!_ballModelLoaded) {
      try {
        final loaded = await loadModels();
        if (!loaded) {
          debugPrint('YOLOv8-Ballmodell konnte nicht geladen werden');
          return DetectionResult.empty();
        }
      } catch (e) {
        debugPrint('Unerwarteter Fehler beim Laden des YOLOv8-Ballmodells: $e');
        return DetectionResult.empty();
      }
    }

    try {
      // Rotationsparameter je nach Plattform und Kamera
      int rotation = 0;
      if (Platform.isAndroid) {
        rotation = isFrontCamera ? 270 : 90;
      }

      // Parameter für nativen Aufruf vorbereiten
      final Map<String, dynamic> arguments = {
        'imageBytes': image.planes[0].bytes,
        'width': image.width,
        'height': image.height,
        'rotation': rotation,
        'isFrontCamera': isFrontCamera,
      };

      // YUV420-Daten hinzufügen, falls verfügbar (für bessere Farbkonvertierung)
      if (image.format.group == ImageFormatGroup.yuv420) {
        if (image.planes.length >= 3) {
          arguments['uPlane'] = image.planes[1].bytes;
          arguments['vPlane'] = image.planes[2].bytes;
          arguments['uvRowStride'] = image.planes[1].bytesPerRow;
          arguments['uvPixelStride'] = image.planes[1].bytesPerPixel ?? 1;
        }
      }

      // Native Ballerkennung aufrufen
      final Map<String, dynamic>? result =
          await _ballChannel.invokeMapMethod('detectBall', arguments);

      if (result == null) {
        return DetectionResult.empty();
      }

      return DetectionResult.fromMap(result);
    } on PlatformException catch (e) {
      debugPrint('Fehler bei der Ballerkennung: ${e.message}');
      return DetectionResult(
        detections: [],
        processingTimeMs: 0,
        error: e.message,
      );
    } catch (e) {
      debugPrint('Unerwarteter Fehler bei der Ballerkennung: $e');
      return DetectionResult(
        detections: [],
        processingTimeMs: 0,
        error: e.toString(),
      );
    }
  }

  /// Gibt alle nativen Ressourcen frei
  static Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
      await _ballChannel.invokeMethod('dispose');
      debugPrint('Native Ressourcen freigegeben');
    } catch (e) {
      debugPrint('Fehler beim Freigeben der nativen Ressourcen: $e');
    }
  }
}

/// Repräsentiert ein erkanntes Objekt (Person oder Ball)
/// mit Bounding-Box und optionalen Keypoints
class DetectedObject {
  final String tag; // Art des Objekts ("person", "soccer_ball")
  final double confidence; // Konfidenz der Erkennung (0-1)
  final List<double> box; // Bounding-Box [x1, y1, x2, y2] (normalisiert 0-1)
  final List<Keypoint>? keypoints; // Keypoints (nur für Personen)

  DetectedObject({
    required this.tag,
    required this.confidence,
    required this.box,
    this.keypoints,
  });

  @override
  String toString() {
    return 'DetectedObject{tag: $tag, confidence: $confidence, box: $box, keypoints: ${keypoints?.length}}';
  }
}

/// Repräsentiert einen Körper-Keypoint (z.B. Schulter, Knie)
/// mit normalisierten Koordinaten und Konfidenzwert
class Keypoint {
  final String name; // Name des Keypoints (z.B. "nose", "left_shoulder")
  final double x; // X-Koordinate (0-1, normalisiert)
  final double y; // Y-Koordinate (0-1, normalisiert)
  final double score; // Konfidenz des Keypoints (0-1)

  Keypoint({
    required this.name,
    required this.x,
    required this.y,
    required this.score,
  });

  @override
  String toString() {
    return 'Keypoint{name: $name, x: $x, y: $y, score: $score}';
  }
}

/// Ergebnis einer Erkennungsoperation, mit erkannten Objekten,
/// Verarbeitungszeit und möglichen Fehlern
class DetectionResult {
  final List<DetectedObject> detections; // Liste erkannter Objekte
  final int processingTimeMs; // Verarbeitungszeit in Millisekunden
  final String? error; // Fehlermeldung, falls vorhanden
  final int inferenceTimeMs; // Reine ML-Inferenzzeit in Millisekunden

  DetectionResult({
    required this.detections,
    required this.processingTimeMs,
    this.error,
    this.inferenceTimeMs = 0,
  });

  /// Erstellt ein leeres Erkennungsergebnis
  factory DetectionResult.empty() {
    return DetectionResult(
      detections: [],
      processingTimeMs: 0,
      inferenceTimeMs: 0,
    );
  }

  /// Konvertiert eine Map aus dem nativen Code in ein DetectionResult
  factory DetectionResult.fromMap(Map<String, dynamic> map) {
    try {
      debugPrint('Verarbeite Erkennungsergebnis');

      final List<dynamic>? detectionsList = map['detections'] as List<dynamic>?;
      final List<DetectedObject> detections = [];

      if (detectionsList != null) {
        debugPrint('Gefundene Detektionen: ${detectionsList.length}');

        for (var detection in detectionsList) {
          try {
            if (detection is! Map) {
              debugPrint('Ungültiges Detektionsformat: $detection');
              continue;
            }

            final Map<String, dynamic> detectionMap = {};

            final Map origMap = detection as Map;
            origMap.forEach((key, value) {
              if (key is String) {
                detectionMap[key] = value;
              }
            });

            if (!detectionMap.containsKey('tag') ||
                !detectionMap.containsKey('box')) {
              debugPrint('Fehlende Felder in der Detektion: $detectionMap');
              continue;
            }

            final String tag = detectionMap['tag'] as String;

            // Konfidenzwert aus 'confidence' oder alternativ 'score' extrahieren
            double confidence = 0.0;
            if (detectionMap.containsKey('confidence')) {
              final dynamic confValue = detectionMap['confidence'];
              confidence = confValue is double
                  ? confValue
                  : (confValue as num).toDouble();
            } else if (detectionMap.containsKey('score')) {
              final dynamic scoreValue = detectionMap['score'];
              confidence = scoreValue is double
                  ? scoreValue
                  : (scoreValue as num).toDouble();
            }

            // Bounding-Box extrahieren und validieren
            final dynamic boxValue = detectionMap['box'];
            List<dynamic> boxDynamic;

            if (boxValue is List) {
              boxDynamic = boxValue;
            } else {
              debugPrint('Box ist kein Array: $boxValue');
              continue;
            }

            final List<double> box = [];
            try {
              for (var value in boxDynamic) {
                box.add(value is double ? value : (value as num).toDouble());
              }

              if (box.length != 4) {
                debugPrint('Box hat nicht 4 Werte: $box');
                continue;
              }
            } catch (e) {
              debugPrint('Fehler bei Box-Verarbeitung: $e');
              continue;
            }

            // Keypoints extrahieren, falls vorhanden (für Personen)
            List<Keypoint>? keypoints;
            if (detectionMap.containsKey('keypoints')) {
              try {
                final dynamic keypointsValue = detectionMap['keypoints'];
                if (keypointsValue is List) {
                  keypoints = [];
                  for (var kp in keypointsValue) {
                    if (kp is Map) {
                      final Map<String, dynamic> keypointMap = {};
                      (kp as Map).forEach((key, value) {
                        if (key is String) {
                          keypointMap[key] = value;
                        }
                      });

                      if (keypointMap.containsKey('name') &&
                          keypointMap.containsKey('x') &&
                          keypointMap.containsKey('y') &&
                          keypointMap.containsKey('score')) {
                        final name = keypointMap['name'] as String;
                        final x = keypointMap['x'] is double
                            ? keypointMap['x'] as double
                            : (keypointMap['x'] as num).toDouble();
                        final y = keypointMap['y'] is double
                            ? keypointMap['y'] as double
                            : (keypointMap['y'] as num).toDouble();
                        final score = keypointMap['score'] is double
                            ? keypointMap['score'] as double
                            : (keypointMap['score'] as num).toDouble();

                        keypoints.add(Keypoint(
                          name: name,
                          x: x,
                          y: y,
                          score: score,
                        ));
                      }
                    }
                  }
                }
              } catch (e) {
                debugPrint('Fehler bei Keypoint-Verarbeitung: $e');
              }
            }

            // DetectedObject erstellen und zur Liste hinzufügen
            detections.add(DetectedObject(
              tag: tag,
              confidence: confidence,
              box: box,
              keypoints: keypoints,
            ));

            debugPrint(
                'Detektion verarbeitet: $tag (${confidence.toStringAsFixed(2)}) mit ${keypoints?.length ?? 0} Keypoints');
          } catch (e) {
            debugPrint('Fehler beim Parsen einer Detektion: $e');
          }
        }
      }

      final int processingTimeMs = map.containsKey('processingTimeMs')
          ? (map['processingTimeMs'] as int?) ?? 0
          : 0;

      final int inferenceTimeMs = map.containsKey('inferenceTimeMs')
          ? (map['inferenceTimeMs'] as int?) ?? 0
          : 0;

      return DetectionResult(
        detections: detections,
        processingTimeMs: processingTimeMs,
        inferenceTimeMs: inferenceTimeMs,
        error: map['error'] as String?,
      );
    } catch (e) {
      debugPrint('Fehler beim Parsen des Erkennungsergebnisses: $e');
      return DetectionResult.empty();
    }
  }

  @override
  String toString() {
    return 'DetectionResult{detections: ${detections.length}, processingTimeMs: $processingTimeMs, error: $error}';
  }
}
