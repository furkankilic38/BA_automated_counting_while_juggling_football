/// ===========================================
/// Autor: Furkan Kilic
/// Beschreibung: Native Detection Service für die Footballista-App.
/// Stellt eine Brücke zwischen dem Flutter-Framework und den nativen Erkennungsfunktionen
/// für Körperposen und Fußbälle bereit.
/// ===========================================
library;

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class NativeDetectionService {
  static const MethodChannel _channel =
      MethodChannel('com.example.footy_testing/detection');
  static const MethodChannel _ballChannel =
      MethodChannel('com.example.footy_testing/ball_detection');

  static bool _modelsLoaded = false;
  static bool _ballModelLoaded = false;

  static Future<bool> loadModels(
      {bool useGpu = false, int retryCount = 1}) async {
    try {
      debugPrint('Lade Erkennungsmodelle, Versuche: $retryCount');

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

  static Future<DetectionResult> detectObjects(CameraImage image,
      {bool isFrontCamera = false}) async {
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
      int rotation = 0;
      if (Platform.isAndroid) {
        rotation = isFrontCamera ? 270 : 90;
      }
      debugPrint(
          'Kamera-Rotation: $rotation Grad, Frontkamera: $isFrontCamera');

      final Map<String, dynamic> arguments = {
        'imageBytes': image.planes[0].bytes,
        'width': image.width,
        'height': image.height,
        'rotation': rotation,
        'iouThreshold': 0.25,
        'confThreshold': 0.01,
        'isFrontCamera': isFrontCamera,
      };

      if (image.format.group == ImageFormatGroup.yuv420) {
        if (image.planes.length >= 3) {
          arguments['uPlane'] = image.planes[1].bytes;
          arguments['vPlane'] = image.planes[2].bytes;
          arguments['uvRowStride'] = image.planes[1].bytesPerRow;
          arguments['uvPixelStride'] = image.planes[1].bytesPerPixel ?? 1;
          debugPrint('YUV420-Format erkannt, sende alle Planes');
        }
      }

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

  static Future<String> testConnection() async {
    try {
      final String result = await _channel.invokeMethod('getTestString');
      return result;
    } on PlatformException catch (e) {
      return 'Fehler: ${e.message}';
    }
  }

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

  static Future<DetectionResult> detectBall(CameraImage image,
      {bool isFrontCamera = false}) async {
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
      int rotation = 0;
      if (Platform.isAndroid) {
        rotation = isFrontCamera ? 270 : 90;
      }

      final Map<String, dynamic> arguments = {
        'imageBytes': image.planes[0].bytes,
        'width': image.width,
        'height': image.height,
        'rotation': rotation,
        'isFrontCamera': isFrontCamera,
      };

      if (image.format.group == ImageFormatGroup.yuv420) {
        if (image.planes.length >= 3) {
          arguments['uPlane'] = image.planes[1].bytes;
          arguments['vPlane'] = image.planes[2].bytes;
          arguments['uvRowStride'] = image.planes[1].bytesPerRow;
          arguments['uvPixelStride'] = image.planes[1].bytesPerPixel ?? 1;
        }
      }

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

class DetectedObject {
  final String tag;
  final double confidence;
  final List<double> box;
  final List<Keypoint>? keypoints;

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

class Keypoint {
  final String name;
  final double x;
  final double y;
  final double score;

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

class DetectionResult {
  final List<DetectedObject> detections;
  final int processingTimeMs;
  final String? error;
  final int inferenceTimeMs;

  DetectionResult({
    required this.detections,
    required this.processingTimeMs,
    this.error,
    this.inferenceTimeMs = 0,
  });

  factory DetectionResult.empty() {
    return DetectionResult(
      detections: [],
      processingTimeMs: 0,
      inferenceTimeMs: 0,
    );
  }

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
