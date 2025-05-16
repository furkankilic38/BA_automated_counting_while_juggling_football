/// ===========================================
/// Autor: Furkan Kilic
/// Beschreibung: Implementierung der Jonglierzähl-Seite der Footballista-App.
/// Verwendet die Kamera und KI-Modelle zur Erkennung und Zählung von Fußball-Jonglierübungen
/// in Echtzeit.
/// ===========================================
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'native_detection_service.dart';
import 'database_helper.dart';

class EnhancedJuggleCounterPage extends StatefulWidget {
  const EnhancedJuggleCounterPage({super.key});

  @override
  _EnhancedJuggleCounterPageState createState() =>
      _EnhancedJuggleCounterPageState();
}

class _EnhancedJuggleCounterPageState extends State<EnhancedJuggleCounterPage> {
  CameraController? _cameraController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isInitialized = false;
  bool _isDetecting = false;

  List<Offset> _ballTrajectory = [];
  final int _maxTrajectoryLength = 40;
  final int _maxPositionHistory = 10;

  int _fps = 0;
  int _processingTimeMs = 0;
  double _avgProcessingTime = 0;
  int _frameCount = 0;

  int _framesInLastSecond = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  String _statusMessage = "Initialisiere...";

  DetectionResult? _lastDetectionResult;
  double? _kneeLineY;
  Rect? _personBoundingBox;
  Rect? _ballBoundingBox;

  final int _targetFps = 10;
  int _frameSkip = 0;
  final int _maxFrameSkip = 3;
  DateTime? _lastFrameTime;

  bool _isDebugMode = false;
  bool _isTorchOn = false;

  List<PoseKeypoint> poseKeypoints = [];

  CameraImage? _lastCameraImage;

  Timer? _ballDetectionTimer;
  int _failedBallDetections = 0;
  static const int _maxFailedBallDetections = 5;

  int _juggleCount = 0;
  bool _isMovingDown = false;
  double? _lastBallCenterY;
  List<double> _ballHeightHistory = [];
  static const int _maxBallHistorySize = 15;

  bool _isCameraInitializing = true;

  CameraLensDirection _cameraDirection = CameraLensDirection.back;

  DateTime? _lastJuggleTime;

  List<double> _shinPositionHistory = [];
  int _shinPositionHistoryMaxLength = 5;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeDetection();

    _initAudioPlayer();

    Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _fps = _framesInLastSecond;
        _framesInLastSecond = 0;
        _lastFpsUpdate = DateTime.now();
      });
    });
  }

  void _initAudioPlayer() async {
    await _audioPlayer.setSource(AssetSource('zaehlsound.mp3'));
    await _audioPlayer.setVolume(1.0);
  }

  @override
  void dispose() {
    _ballDetectionTimer?.cancel();
    _cameraController?.dispose();
    NativeDetectionService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _statusMessage = "Kamera wird initialisiert...";
        _isCameraInitializing = true;
      });

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _statusMessage = "Keine Kameras verfügbar!";
          _isCameraInitializing = false;
        });
        return;
      }

      print("Verfügbare Kameras: ${cameras.length}");
      for (var i = 0; i < cameras.length; i++) {
        print("Kamera $i: ${cameras[i].name}, ${cameras[i].lensDirection}");
      }

      CameraDescription selectedCamera = cameras[0];
      for (var camera in cameras) {
        if (camera.lensDirection == _cameraDirection) {
          selectedCamera = camera;
          break;
        }
      }

      if (_cameraController != null) {
        await _cameraController!.dispose();
      }

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      try {
        if (Platform.isAndroid) {
          await _cameraController!.setExposureOffset(-1.0);
        }
      } catch (e) {
        print("Konnte Kamera-Parameter nicht optimieren: $e");
      }

      print("Kamera initialisiert: ${_cameraController!.description.name}");
      print("Vorschaugröße: ${_cameraController!.value.previewSize}");
      print("Format-Gruppe: ${_cameraController!.imageFormatGroup}");
      print("Auflösung: ${_cameraController!.resolutionPreset}");

      setState(() {
        _statusMessage = "Kamera bereit";
        _isCameraInitializing = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Kamera-Fehler: $e";
        _isCameraInitializing = false;
      });
      print("Kamera-Initialisierungsfehler: $e");
    }
  }

  Future<void> _initializeDetection() async {
    try {
      setState(() {
        _statusMessage = "Lade Modelle...";
      });

      print("=== STARTE MODELL-INITIALISIERUNG ===");

      await _checkAssets();

      print("Versuche YOLO-Modell zu laden...");

      bool result =
          await NativeDetectionService.loadModels(useGpu: true, retryCount: 3);

      setState(() {
        _isInitialized = result;
        _statusMessage = result
            ? "Modelle geladen, bereit zum Starten"
            : "⚠️ Fehler beim Laden der Modelle";
      });

      print("Initialisierungsergebnis: $result");

      final testResult = await NativeDetectionService.testConnection();
      print("Verbindungstest: $testResult");

      if (!result) {
        _showModelErrorDialog();
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Detektions-Fehler: $e";
      });
      print("Detektions-Initialisierungsfehler: $e");
    }
  }

  void _showModelErrorDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Modell-Ladung fehlgeschlagen"),
          content: Text(
              "Das KI-Modell konnte nicht geladen werden. Mögliche Gründe:\n\n"
              "1. Gerät unterstützt das Modellformat nicht\n"
              "2. Zu wenig Arbeitsspeicher verfügbar\n"
              "3. Das Modell ist beschädigt\n\n"
              "Versuche, die App neu zu starten oder auf einem anderen Gerät zu testen."),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Erneut versuchen"),
              onPressed: () {
                Navigator.of(context).pop();
                _initializeDetection();
              },
            ),
          ],
        );
      },
    );
  }

  void _handleDetectionResult(DetectionResult detectionResult) {
    if (!mounted) return;

    setState(() {
      _processingTimeMs = detectionResult.processingTimeMs;
      _lastDetectionResult = detectionResult;

      _framesInLastSecond++;
      final now = DateTime.now();
      if (now.difference(_lastFpsUpdate) >= Duration(seconds: 1)) {
        _fps = _framesInLastSecond;
        _framesInLastSecond = 0;
        _lastFpsUpdate = now;
      }

      _frameCount++;
      _avgProcessingTime =
          (_avgProcessingTime * (_frameCount - 1) + _processingTimeMs) /
              _frameCount;

      DetectedObject? detectedPerson;

      for (var detection in detectionResult.detections) {
        if (detection.tag.toLowerCase() == 'person') {
          detectedPerson = detection;
          break;
        }
      }

      print("Erkannte Objekte: ${detectionResult.detections.length}");
      for (var det in detectionResult.detections) {
        print("  - ${det.tag} (${det.confidence.toStringAsFixed(2)})");
        if (det.keypoints != null) {
          print("    Keypoints: ${det.keypoints!.length}");
          for (var kp in det.keypoints!.take(5)) {
            print(
                "    - ${kp.name}: (${kp.x.toStringAsFixed(2)}, ${kp.y.toStringAsFixed(2)}) score=${kp.score.toStringAsFixed(2)}");
          }
        }
      }

      if (detectedPerson != null && detectedPerson.box.length == 4) {
        final box = detectedPerson.box;
        final previewSize = _cameraController!.value.previewSize!;

        _personBoundingBox = Rect.fromLTRB(
          box[0] * previewSize.width,
          box[1] * previewSize.height,
          box[2] * previewSize.width,
          box[3] * previewSize.height,
        );

        if (detectedPerson.keypoints != null &&
            detectedPerson.keypoints!.isNotEmpty) {
          poseKeypoints = detectedPerson.keypoints!.map((keypoint) {
            return PoseKeypoint(
              name: keypoint.name,
              position: Offset(keypoint.x * previewSize.width,
                  keypoint.y * previewSize.height),
              confidence: keypoint.score,
            );
          }).toList();

          print("✅ Pose-Keypoints erkannt: ${poseKeypoints.length}");
          print(
              "   - Anzahl Keypoints mit Konfidenz > 0.3: ${poseKeypoints.where((kp) => kp.confidence > 0.3).length}");
          print(
              "   - Mittlere Konfidenz: ${poseKeypoints.map((kp) => kp.confidence).reduce((a, b) => a + b) / poseKeypoints.length}");

          Keypoint? leftKnee, rightKnee, leftAnkle, rightAnkle;

          for (var keypoint in detectedPerson.keypoints!) {
            if (keypoint.name == 'left_knee' && keypoint.score > 0.3) {
              leftKnee = keypoint;
            } else if (keypoint.name == 'right_knee' && keypoint.score > 0.3) {
              rightKnee = keypoint;
            } else if (keypoint.name == 'left_ankle' && keypoint.score > 0.3) {
              leftAnkle = keypoint;
            } else if (keypoint.name == 'right_ankle' && keypoint.score > 0.3) {
              rightAnkle = keypoint;
            }
          }

          if ((leftKnee != null && leftAnkle != null) ||
              (rightKnee != null && rightAnkle != null)) {
            double currentShinY = 0;
            int count = 0;

            if (leftKnee != null && leftAnkle != null) {
              double leftShinY =
                  (leftKnee.y + leftAnkle.y) / 2 * previewSize.height;
              currentShinY += leftShinY;
              count++;
            }

            if (rightKnee != null && rightAnkle != null) {
              double rightShinY =
                  (rightKnee.y + rightAnkle.y) / 2 * previewSize.height;
              currentShinY += rightShinY;
              count++;
            }

            if (count > 0) {
              currentShinY = currentShinY / count;

              _shinPositionHistory.add(currentShinY);
              if (_shinPositionHistory.length > _shinPositionHistoryMaxLength) {
                _shinPositionHistory.removeAt(0);
              }

              double smoothedShinY = 0;

              if (_shinPositionHistory.isNotEmpty) {
                double totalWeight = 0;
                double weightedSum = 0;

                for (int i = 0; i < _shinPositionHistory.length; i++) {
                  double weight = (i + 1);
                  weightedSum += _shinPositionHistory[i] * weight;
                  totalWeight += weight;
                }

                smoothedShinY = weightedSum / totalWeight;
              } else {
                smoothedShinY = currentShinY;
              }

              _kneeLineY = smoothedShinY;

              if (_isDebugMode) {
                print(
                    "🦵 Schienbein-Linie aktualisiert: Y=${_kneeLineY!.toStringAsFixed(1)}");
                if (_shinPositionHistory.length > 1) {
                  double movement =
                      _shinPositionHistory.last - _shinPositionHistory.first;
                  String direction =
                      movement > 0 ? "⬇️ abwärts" : "⬆️ aufwärts";
                  print(
                      "   Bewegung: $direction (${movement.abs().toStringAsFixed(1)}px)");
                }
              }
            }
          }
        } else {
          poseKeypoints = [];
          print("❌ Keine Pose-Keypoints erkannt");
        }
      } else {
        _personBoundingBox = null;
      }
    });
  }

  Future<void> _detectSoccerBall() async {
    if (!mounted ||
        !_isDetecting ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _lastCameraImage == null) {
      return;
    }

    try {
      final ballDetectionResult = await NativeDetectionService.detectBall(
          _lastCameraImage!,
          isFrontCamera: _cameraDirection == CameraLensDirection.front);

      if (!mounted) return;

      if (ballDetectionResult.error != null) {
        if (_isDebugMode) {
          print(
              "⚠️ Fehler bei der Ballerkennung: ${ballDetectionResult.error}");
        }
        _failedBallDetections++;
        return;
      }

      setState(() {
        DetectedObject? detectedBall;
        for (var detection in ballDetectionResult.detections) {
          if (detection.tag.toLowerCase().contains('ball') ||
              detection.tag.toLowerCase().contains('sports') ||
              detection.tag.toLowerCase() == 'soccer_ball') {
            detectedBall = detection;
            break;
          }
        }

        if (detectedBall != null && detectedBall.box.length == 4) {
          _failedBallDetections = 0;

          final confidence = detectedBall.confidence;
          final box = detectedBall.box;
          final previewSize = _cameraController!.value.previewSize!;

          if (_isDebugMode && _fps % 10 == 0) {
            print("⚽ Ball erkannt: Konfidenz=${confidence.toStringAsFixed(2)}");
          }

          _ballBoundingBox = Rect.fromLTRB(
            box[0] * previewSize.width,
            box[1] * previewSize.height,
            box[2] * previewSize.width,
            box[3] * previewSize.height,
          );

          final ballCenterX =
              (_ballBoundingBox!.left + _ballBoundingBox!.right) / 2;
          final ballCenterY =
              (_ballBoundingBox!.top + _ballBoundingBox!.bottom) / 2;
          final ballPosition = Offset(ballCenterX, ballCenterY);

          if (_ballTrajectory.isEmpty ||
              (_ballTrajectory.last - ballPosition).distance > 5) {
            _ballTrajectory.add(ballPosition);
            if (_ballTrajectory.length > _maxTrajectoryLength) {
              _ballTrajectory.removeAt(0);
            }
          }

          _checkBallCrossedKneeLine(ballCenterY);

          _lastBallCenterY = ballCenterY;
        } else {
          _failedBallDetections++;

          if (_isDebugMode && _failedBallDetections % 5 == 0) {
            print(
                "❌ Kein Ball erkannt (${_failedBallDetections}/${_maxFailedBallDetections})");
          }

          if (_failedBallDetections >= _maxFailedBallDetections) {
            _ballBoundingBox = null;
            if (_isDebugMode) {
              print(
                  "🔄 Ball-Box zurückgesetzt nach ${_maxFailedBallDetections} fehlgeschlagenen Erkennungen");
            }
          }
        }
      });
    } catch (e) {
      _failedBallDetections++;
      if (_isDebugMode) {
        print("🚨 Fehler bei der Ballerkennung: $e");
      }
    }
  }

  void _checkBallCrossedKneeLine(double ballCenterY) {
    if (_lastBallCenterY == null) {
      return;
    }

    bool enoughTimePassed = true;
    if (_lastJuggleTime != null) {
      final now = DateTime.now();
      final timeSinceLastJuggle =
          now.difference(_lastJuggleTime!).inMilliseconds;
      enoughTimePassed = timeSinceLastJuggle > 50;
    }

    bool isNowMovingDown = ballCenterY > _lastBallCenterY!;
    bool directionChanged = isNowMovingDown != _isMovingDown;

    _ballHeightHistory.add(ballCenterY);
    if (_ballHeightHistory.length > _maxBallHistorySize) {
      _ballHeightHistory.removeAt(0);
    }

    if (_isMovingDown && !isNowMovingDown && enoughTimePassed) {
      if (_ballHeightHistory.length >= 3) {
        double highestPoint =
            _ballHeightHistory.reduce((a, b) => a < b ? a : b);
        double lowestPoint = _ballHeightHistory.reduce((a, b) => a > b ? a : b);
        double verticalRange = lowestPoint - highestPoint;

        if (verticalRange > 15 && !isNowMovingDown) {
          setState(() {
            _juggleCount++;
            _lastJuggleTime = DateTime.now();
          });

          _playCountSound();

          if (_isDebugMode) {
            print(
                "🎯 JUGGLE #$_juggleCount ERKANNT! (Methode 1: Richtungswechsel)");
            print(
                "   Bewegungsbereich: ${verticalRange.toStringAsFixed(1)}px, Wendepunkt bei ${ballCenterY.toStringAsFixed(1)}");

            if (_ballHeightHistory.length > 3) {
              String graph = "   Verlauf: ";
              for (int i = 0; i < _ballHeightHistory.length - 1; i++) {
                double diff = _ballHeightHistory[i] - _ballHeightHistory[i + 1];
                if (diff > 5)
                  graph += "⬆️";
                else if (diff < -5)
                  graph += "⬇️";
                else
                  graph += "➡️";
              }
              print(graph);
            }
          }

          _ballHeightHistory.clear();
          _lastBallCenterY = ballCenterY;
          _isMovingDown = isNowMovingDown;
          return;
        }
      }
    }

    if (_ballHeightHistory.length >= 4 && enoughTimePassed) {
      double y0 = _ballHeightHistory[_ballHeightHistory.length - 4];
      double y1 = _ballHeightHistory[_ballHeightHistory.length - 3];
      double y2 = _ballHeightHistory[_ballHeightHistory.length - 2];
      double y3 = _ballHeightHistory[_ballHeightHistory.length - 1];

      double v01 = y1 - y0;
      double v12 = y2 - y1;
      double v23 = y3 - y2;

      double acc1 = v12 - v01;
      double acc2 = v23 - v12;

      if ((acc1 > 1 && acc2 < -8 && v23 < 0) || (acc1 > 0 && acc2 < -12)) {
        setState(() {
          _juggleCount++;
          _lastJuggleTime = DateTime.now();
        });

        _playCountSound();

        if (_isDebugMode) {
          print(
              "🎯 JUGGLE #$_juggleCount ERKANNT! (Methode 2: Beschleunigungsanalyse)");
          print(
              "   Beschleunigungen: ${acc1.toStringAsFixed(1)} → ${acc2.toStringAsFixed(1)}, v1=${v01.toStringAsFixed(1)}, v2=${v12.toStringAsFixed(1)}, v3=${v23.toStringAsFixed(1)}");
        }

        _ballHeightHistory.clear();
        _lastBallCenterY = ballCenterY;
        _isMovingDown = isNowMovingDown;
        return;
      }
    }

    if (_ballHeightHistory.length >= 5 && enoughTimePassed) {
      List<bool> directions = [];
      for (int i = 0; i < _ballHeightHistory.length - 1; i++) {
        directions.add(_ballHeightHistory[i] < _ballHeightHistory[i + 1]);
      }
      bool hasChangeDown = false;
      bool hasChangeUp = false;
      for (int i = 0; i < directions.length - 1; i++) {
        if (directions[i] && !directions[i + 1]) {
          hasChangeDown = true;
        }
        if (!directions[i] && directions[i + 1]) {
          hasChangeUp = true;
        }
      }
      double minY = _ballHeightHistory.reduce((a, b) => a < b ? a : b);
      double maxY = _ballHeightHistory.reduce((a, b) => a > b ? a : b);
      double totalRange = maxY - minY;

      if ((hasChangeDown || hasChangeUp) && totalRange > 10) {
        bool lastMovementUp = directions.last == false;
        bool significantMovement = totalRange > 25;

        if (lastMovementUp || significantMovement) {
          setState(() {
            _juggleCount++;
            _lastJuggleTime = DateTime.now();
          });

          _playCountSound();

          if (_isDebugMode) {
            print(
                "🎯 JUGGLE #$_juggleCount ERKANNT! (Methode 3: Richtungswechsel-Muster)");
            print(
                "   Bewegungsbereich: ${totalRange.toStringAsFixed(1)}px, Wechsel erkannt");
            String dirStr = "";
            for (bool dir in directions) {
              dirStr += dir ? "⬇️" : "⬆️";
            }
            print("   Richtungsverlauf: $dirStr");
          }
          _ballHeightHistory.clear();
          _lastBallCenterY = ballCenterY;
          _isMovingDown = isNowMovingDown;
          return;
        }
      }
    }

    if (_kneeLineY != null &&
        _ballHeightHistory.length >= 3 &&
        enoughTimePassed) {
      double ballToKneeDistance = (_kneeLineY! - ballCenterY).abs();

      bool isNearKneeLine = ballToKneeDistance < 50;

      double recentYMovement = 0;
      if (_ballHeightHistory.length >= 3) {
        double y1 = _ballHeightHistory[_ballHeightHistory.length - 3];
        double y3 = _ballHeightHistory[_ballHeightHistory.length - 1];
        recentYMovement = y3 - y1;
      }

      bool hasUpwardMovement = recentYMovement < -5;

      if (isNearKneeLine &&
          hasUpwardMovement &&
          directionChanged &&
          !isNowMovingDown) {
        setState(() {
          _juggleCount++;
          _lastJuggleTime = DateTime.now();
        });

        _playCountSound();

        if (_isDebugMode) {
          print(
              "🎯 JUGGLE #$_juggleCount ERKANNT! (Methode 4: Schienbein-Interaktion)");
          print(
              "   Ball-Schienbein-Distanz: ${ballToKneeDistance.toStringAsFixed(1)}px");
          print("   Aufwärtsbewegung: ${recentYMovement.toStringAsFixed(1)}px");
        }

        _ballHeightHistory.clear();
        _lastBallCenterY = ballCenterY;
        _isMovingDown = isNowMovingDown;
        return;
      }
    }

    _isMovingDown = isNowMovingDown;
    _lastBallCenterY = ballCenterY;

    if (_isDebugMode && _fps % 15 == 0) {
      print(
          "🔍 Ball bewegt sich ${_isMovingDown ? "⬇️ ABWÄRTS" : "⬆️ AUFWÄRTS"} (Y=${ballCenterY.toStringAsFixed(1)})");
      if (_ballHeightHistory.length > 1) {
        double recentMovement = _ballHeightHistory.last -
            _ballHeightHistory[_ballHeightHistory.length - 2];
        print("   Letzte Bewegung: ${recentMovement.toStringAsFixed(1)}px");
      }

      if (_kneeLineY != null) {
        double ballToKneeDistance = (_kneeLineY! - ballCenterY).abs();
        print(
            "   Distanz zur Schienbein-Linie: ${ballToKneeDistance.toStringAsFixed(1)}px");
      }
    }
  }

  void _playCountSound() async {
    try {
      await _audioPlayer.play(AssetSource('zaehlsound.mp3'));
    } catch (e) {
      if (_isDebugMode) {
        print("Fehler beim Abspielen des Sounds: $e");
      }
    }
  }

  Future<void> _checkAssets() async {
    try {
      final assetPaths = [
        'assets/yolov8n_int8.tflite',
        'assets/labels.txt',
      ];

      print("Überprüfe Asset-Pfade:");
      for (final path in assetPaths) {
        try {
          final ByteData data = await rootBundle.load(path);
          print("✓ $path (${data.lengthInBytes} Bytes)");
        } catch (e) {
          print("✕ $path (FEHLER: $e)");
        }
      }
    } catch (e) {
      print("Fehler beim Überprüfen der Assets: $e");
    }
  }

  Future<void> _startDetection() async {
    if (_isDetecting) return;

    if (!_isInitialized) {
      setState(() {
        _statusMessage = "Modelle noch nicht geladen!";
      });
      return;
    }

    setState(() {
      _isDetecting = true;
      _statusMessage = "Erkennung läuft...";
      _failedBallDetections = 0;
      _isDebugMode = true;
      _frameSkip = 0;
      _lastFrameTime = null;
    });

    print("🐞 Debug-Modus aktiviert");
    print("⚡ Optimierte Performance-Einstellungen aktiv");

    try {
      bool isCurrentlyProcessing = false;
      int totalFrames = 0;
      int droppedFrames = 0;
      DateTime performanceTrackingStart = DateTime.now();

      await _cameraController!.startImageStream((CameraImage image) {
        if (!_isDetecting) return;

        _lastCameraImage = image;
        totalFrames++;

        if (totalFrames % 30 == 0) {
          final duration =
              DateTime.now().difference(performanceTrackingStart).inSeconds;
          if (duration > 0) {
            final captureRate = totalFrames / duration;
            final processedRate = (totalFrames - droppedFrames) / duration;
            final dropRate = (droppedFrames / totalFrames) * 100;
            print(
                "📊 PERF: Capture=${captureRate.toStringAsFixed(1)} FPS, Processed=${processedRate.toStringAsFixed(1)} FPS, Dropped=${dropRate.toStringAsFixed(1)}%");
          }
        }

        if (isCurrentlyProcessing) {
          droppedFrames++;
          return;
        }

        final now = DateTime.now();
        if (_lastFrameTime != null) {
          final elapsed = now.difference(_lastFrameTime!).inMilliseconds;
          if (elapsed < 1000 / (_targetFps + 2)) {
            droppedFrames++;
            return;
          }
        }
        _lastFrameTime = now;

        isCurrentlyProcessing = true;

        NativeDetectionService.detectObjects(image,
                isFrontCamera: _cameraDirection == CameraLensDirection.front)
            .then((result) {
          isCurrentlyProcessing = false;

          if (!mounted) return;

          if (result.error != null) {
            print("⚠️ Erkennungsfehler: ${result.error}");
          }

          _handleDetectionResult(result);

          if (_lastCameraImage != null) {
            _detectSoccerBall();
          }

          if (_isDebugMode && totalFrames % 10 == 0) {
            print(
                "📊 STATS: FPS=$_fps, Verarbeitungszeit=${result.processingTimeMs}ms, Inferenz=${result.inferenceTimeMs}ms");
          }
        }).catchError((e) {
          isCurrentlyProcessing = false;
          print("🚨 Fehler während der Detektion: $e");
        });
      });

      setState(() {
        _statusMessage = "Erkennung aktiv (kontinuierliches Ball-Tracking)";
      });
    } catch (e) {
      setState(() {
        _isDetecting = false;
        _statusMessage = "Fehler: $e";
      });
      print("🚨 Fehler beim Starten der Detektion: $e");
    }
  }

  void _stopDetection() async {
    if (!_isDetecting) return;

    setState(() {
      _isDetecting = false;
      _statusMessage = "Erkennung gestoppt";
    });

    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      print("Fehler beim Stoppen der Bildaufnahme: $e");
    }

    if (_juggleCount > 0) {
      try {
        await DatabaseHelper.instance.addJuggleCount(_juggleCount);

        if (_isDebugMode) {
          print(
              "📊 Jonglier-Ergebnis ($_juggleCount) in Datenbank gespeichert");
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_juggleCount Juggles gespeichert!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        print("Fehler beim Speichern des Juggle-Counts: $e");

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern der Juggles: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    setState(() {
      _ballBoundingBox = null;
      _ballTrajectory.clear();
      _failedBallDetections = 0;
    });
  }

  void _resetCounter() {
    setState(() {
      _ballTrajectory.clear();
      _juggleCount = 0;
      _ballHeightHistory.clear();
    });

    if (_isDebugMode) {
      print("🔄 Jonglierzähler zurückgesetzt");
    }
  }

  void _toggleCamera() async {
    if (_isDetecting) {
      _stopDetection();
    }

    setState(() {
      _cameraDirection = (_cameraDirection == CameraLensDirection.back)
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      _isCameraInitializing = true;
      _statusMessage = "Wechsle Kamera...";
    });

    await _initializeCamera();

    if (_isDetecting) {
      _startDetection();
    }
  }

  void _toggleTorch() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCameraInitializing) {
      return;
    }

    try {
      final bool newTorchState = !_isTorchOn;
      await _cameraController!.setFlashMode(
        newTorchState ? FlashMode.torch : FlashMode.off,
      );
      setState(() {
        _isTorchOn = newTorchState;
      });
    } catch (e) {
      print("Fehler beim Umschalten der Taschenlampe: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          _buildUI(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_isCameraInitializing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              "Kamera wird initialisiert...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            "Kamera nicht verfügbar",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return CameraPreview(_cameraController!);
  }

  Widget _buildUI() {
    return Stack(
      children: [
        if (!_isCameraInitializing &&
            _cameraController != null &&
            _cameraController!.value.isInitialized &&
            _lastDetectionResult != null)
          Container(
            width: double.infinity,
            height: double.infinity,
            child: CustomPaint(
              painter: PoseDetectionPainter(
                person: _lastDetectionResult?.detections.firstWhere(
                  (det) => det.tag.toLowerCase() == 'person',
                  orElse: () => DetectedObject(
                    tag: 'none',
                    confidence: 0,
                    box: [0, 0, 0, 0],
                  ),
                ),
                ballTrajectory: _ballTrajectory,
                showDebug: _isDebugMode,
                imageSize:
                    _cameraController?.value.previewSize ?? Size(720, 1280),
                ballBoundingBox: _ballBoundingBox,
                isFrontCamera: _cameraDirection == CameraLensDirection.front,
              ),
            ),
          ),
        Positioned(
          top: 40,
          right: 20,
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "Erkennung",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _ballBoundingBox != null ? "Ball ✓" : "Ball ✗",
                  style: TextStyle(
                    color: _ballBoundingBox != null ? Colors.green : Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _personBoundingBox != null ? "Person ✓" : "Person ✗",
                  style: TextStyle(
                    color:
                        _personBoundingBox != null ? Colors.green : Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    "Juggles: $_juggleCount",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 40,
          left: 20,
          child: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Status: $_statusMessage",
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                Text(
                  "FPS: $_fps",
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.orange, size: 14),
                    SizedBox(width: 2),
                    Text(
                      "GPU-BESCHLEUNIGT",
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                if (_isDebugMode)
                  Text(
                    "Processing: $_processingTimeMs ms",
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(
                    _isDebugMode ? Icons.bug_report : Icons.bug_report_outlined,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isDebugMode = !_isDebugMode;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    _cameraDirection == CameraLensDirection.back
                        ? Icons.camera_front
                        : Icons.camera_rear,
                    color: Colors.white,
                  ),
                  onPressed: _isCameraInitializing ? null : _toggleCamera,
                ),
                IconButton(
                  icon: Icon(
                    _isTorchOn ? Icons.flashlight_on : Icons.flashlight_off,
                    color: _isTorchOn ? Colors.yellow : Colors.white,
                  ),
                  onPressed: _cameraDirection == CameraLensDirection.back &&
                          !_isCameraInitializing
                      ? _toggleTorch
                      : null,
                ),
                ElevatedButton.icon(
                  icon: Icon(_isDetecting ? Icons.stop : Icons.play_arrow),
                  label: Text(_isDetecting ? "Stop" : "Start"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDetecting ? Colors.red : Colors.green,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: _isDetecting ? _stopDetection : _startDetection,
                ),
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: Colors.white,
                  ),
                  onPressed: _resetCounter,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebugLayer() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container();
    }

    return CustomPaint(
      size: Size(MediaQuery.of(context).size.width,
          MediaQuery.of(context).size.height),
      painter: PoseDetectionPainter(
        person: _lastDetectionResult?.detections.firstWhere(
          (det) => det.tag.toLowerCase() == 'person',
          orElse: () => DetectedObject(
            tag: 'none',
            confidence: 0,
            box: [0, 0, 0, 0],
          ),
        ),
        ballTrajectory: _ballTrajectory,
        showDebug: true,
        imageSize: _cameraController!.value.previewSize ?? Size(720, 1280),
        ballBoundingBox: _ballBoundingBox,
      ),
    );
  }
}

/**
 * PoseDetectionPainter - Zeichnet Erkennungsdaten auf dem Canvas
 * 
 * Visualisiert Person, Ball und deren Interaktion für Jonglier-Erkennung
 */
class PoseDetectionPainter extends CustomPainter {
  final DetectedObject? person;
  final List<Offset> ballTrajectory;
  final bool showDebug;
  final Size imageSize;
  final Rect? ballBoundingBox;
  final bool isFrontCamera;

  PoseDetectionPainter({
    this.person,
    required this.ballTrajectory,
    this.showDebug = false,
    required this.imageSize,
    this.ballBoundingBox,
    this.isFrontCamera = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (person == null ||
        person!.keypoints == null ||
        person!.keypoints!.isEmpty) {
      return;
    }

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    final double mirrorFactor = isFrontCamera ? -1.0 : 1.0;

    Rect scaledRect = Rect.zero;
    if (person!.box.length == 4) {
      final boxPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      if (isFrontCamera) {
        scaledRect = Rect.fromLTRB(
            size.width - (person!.box[2] * size.width),
            person!.box[1] * size.height,
            size.width - (person!.box[0] * size.width),
            person!.box[3] * size.height);
      } else {
        scaledRect = Rect.fromLTRB(
            person!.box[0] * size.width,
            person!.box[1] * size.height,
            person!.box[2] * size.width,
            person!.box[3] * size.height);
      }

      canvas.drawRect(scaledRect, boxPaint);
    }

    final Map<String, Keypoint> keypointMap = {};
    for (var keypoint in person!.keypoints!) {
      keypointMap[keypoint.name] = keypoint;
    }

    Keypoint? leftKnee = keypointMap['left_knee'];
    Keypoint? rightKnee = keypointMap['right_knee'];
    Keypoint? leftAnkle = keypointMap['left_ankle'];
    Keypoint? rightAnkle = keypointMap['right_ankle'];

    if ((leftKnee != null &&
            leftKnee.score > 0.3 &&
            leftAnkle != null &&
            leftAnkle.score > 0.3) ||
        (rightKnee != null &&
            rightKnee.score > 0.3 &&
            rightAnkle != null &&
            rightAnkle.score > 0.3)) {
      double shinY = 0;
      int count = 0;

      if (leftKnee != null &&
          leftKnee.score > 0.3 &&
          leftAnkle != null &&
          leftAnkle.score > 0.3) {
        double leftShinY = ((leftKnee.y + leftAnkle.y) / 2) * size.height;
        shinY += leftShinY;
        count++;
      }

      if (rightKnee != null &&
          rightKnee.score > 0.3 &&
          rightAnkle != null &&
          rightAnkle.score > 0.3) {
        double rightShinY = ((rightKnee.y + rightAnkle.y) / 2) * size.height;
        shinY += rightShinY;
        count++;
      }

      if (count > 0) {
        shinY = shinY / count;

        final shinLinePaint = Paint()
          ..color = Colors.blue.shade600
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke;

        if (scaledRect != Rect.zero) {
          final shadowPaint = Paint()
            ..color = Colors.black.withOpacity(0.5)
            ..strokeWidth = 5.0
            ..style = PaintingStyle.stroke;

          canvas.drawLine(Offset(scaledRect.left, shinY),
              Offset(scaledRect.right, shinY), shadowPaint);

          canvas.drawLine(Offset(scaledRect.left, shinY),
              Offset(scaledRect.right, shinY), shinLinePaint);

          if (showDebug) {
            final textPainter = TextPainter(
              text: TextSpan(
                text: "Jonglier-Linie",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  backgroundColor: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            textPainter.layout();
            textPainter.paint(canvas, Offset(scaledRect.left + 10, shinY - 20));
          }
        }
      }
    }

    if (ballBoundingBox != null) {
      final ballBoxPaint = Paint()
        ..color = Colors.orange
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      Rect scaledBallRect;
      if (isFrontCamera) {
        scaledBallRect = Rect.fromLTRB(
            size.width - (ballBoundingBox!.right * scaleX),
            ballBoundingBox!.top * scaleY,
            size.width - (ballBoundingBox!.left * scaleX),
            ballBoundingBox!.bottom * scaleY);
      } else {
        scaledBallRect = Rect.fromLTRB(
            ballBoundingBox!.left * scaleX,
            ballBoundingBox!.top * scaleY,
            ballBoundingBox!.right * scaleX,
            ballBoundingBox!.bottom * scaleY);
      }

      canvas.drawRect(scaledBallRect, ballBoxPaint);

      final ballCenter = Offset(
          (scaledBallRect.left + scaledBallRect.right) / 2,
          (scaledBallRect.top + scaledBallRect.bottom) / 2);

      if (ballTrajectory.length >= 2) {}

      if (showDebug) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: "Ball",
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              backgroundColor: Colors.black54,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
            canvas,
            Offset(ballCenter.dx - textPainter.width / 2,
                ballCenter.dy - textPainter.height / 2));
      }
    }

    final List<List<String>> connections = [
      ['left_shoulder', 'right_shoulder'],
      ['left_shoulder', 'left_elbow'],
      ['right_shoulder', 'right_elbow'],
      ['left_elbow', 'left_wrist'],
      ['right_elbow', 'right_wrist'],
      ['left_shoulder', 'left_hip'],
      ['right_shoulder', 'right_hip'],
      ['left_hip', 'right_hip'],
      ['left_hip', 'left_knee'],
      ['right_hip', 'right_knee'],
      ['left_knee', 'left_ankle'],
      ['right_knee', 'right_ankle'],
      ['nose', 'left_eye'],
      ['nose', 'right_eye'],
      ['left_eye', 'left_ear'],
      ['right_eye', 'right_ear'],
    ];

    final Paint linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final Paint dotPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 5.0
      ..style = PaintingStyle.fill;

    for (var connection in connections) {
      final String from = connection[0];
      final String to = connection[1];

      if (keypointMap.containsKey(from) && keypointMap.containsKey(to)) {
        final Keypoint fromKp = keypointMap[from]!;
        final Keypoint toKp = keypointMap[to]!;

        if (fromKp.score > 0.3 && toKp.score > 0.3) {
          final Offset scaledFrom = isFrontCamera
              ? Offset(
                  size.width - (fromKp.x * size.width), fromKp.y * size.height)
              : Offset(fromKp.x * size.width, fromKp.y * size.height);

          final Offset scaledTo = isFrontCamera
              ? Offset(size.width - (toKp.x * size.width), toKp.y * size.height)
              : Offset(toKp.x * size.width, toKp.y * size.height);

          canvas.drawLine(scaledFrom, scaledTo, linePaint);
        }
      }
    }

    for (var keypoint in person!.keypoints!) {
      if (keypoint.score > 0.3) {
        final Offset scaledPoint = isFrontCamera
            ? Offset(size.width - (keypoint.x * size.width),
                keypoint.y * size.height)
            : Offset(keypoint.x * size.width, keypoint.y * size.height);

        Color pointColor;
        double pointSize = 5.0;

        if (keypoint.name.contains('ankle') ||
            keypoint.name.contains('knee') ||
            keypoint.name.contains('hip')) {
          pointColor = Colors.blue;
          if (keypoint.name.contains('ankle')) pointSize = 7.0;
        } else if (keypoint.name.contains('wrist') ||
            keypoint.name.contains('elbow') ||
            keypoint.name.contains('shoulder')) {
          pointColor = Colors.green;
        } else {
          pointColor = Colors.red;
        }

        dotPaint.color = pointColor;
        canvas.drawCircle(scaledPoint, pointSize, dotPaint);

        if (showDebug) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: "${keypoint.name}\n${keypoint.score.toStringAsFixed(2)}",
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                backgroundColor: Colors.black54,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(
              canvas, Offset(scaledPoint.dx + 5, scaledPoint.dy + 5));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/**
 * PoseKeypoint - Einfache Datenklasse für einen Körperpunkt
 * 
 * Speichert Name, Position und Konfidenz eines erkannten Keypoints
 */
class PoseKeypoint {
  final String name;
  final Offset position;
  final double confidence;

  PoseKeypoint({
    required this.name,
    required this.position,
    required this.confidence,
  });
}

/**
 * PoseSkeletonPainter - Vereinfachte Version des Skelett-Zeichners
 * 
 * Zeichnet nur das Skelett ohne Ball und Knie-Linien
 */
class PoseSkeletonPainter extends CustomPainter {
  final List<PoseKeypoint> keypoints;
  final Rect? personBox;
  final bool showSkeleton;
  final double confidenceThreshold;

  PoseSkeletonPainter({
    required this.keypoints,
    this.personBox,
    this.showSkeleton = true,
    this.confidenceThreshold = 0.3,
  });

  static const List<List<String>> edges = [
    ['nose', 'left_eye'],
    ['nose', 'right_eye'],
    ['left_eye', 'left_ear'],
    ['right_eye', 'right_ear'],
    ['left_shoulder', 'right_shoulder'],
    ['left_shoulder', 'left_elbow'],
    ['right_shoulder', 'right_elbow'],
    ['left_elbow', 'left_wrist'],
    ['right_elbow', 'right_wrist'],
    ['left_shoulder', 'left_hip'],
    ['right_shoulder', 'right_hip'],
    ['left_hip', 'right_hip'],
    ['left_hip', 'left_knee'],
    ['right_hip', 'right_knee'],
    ['left_knee', 'left_ankle'],
    ['right_knee', 'right_ankle'],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (!showSkeleton || keypoints.isEmpty) return;

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final jointPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 6.0
      ..style = PaintingStyle.fill;

    if (personBox != null) {
      final boxPaint = Paint()
        ..color = Colors.blue.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(personBox!, boxPaint);
    }

    for (var keypoint in keypoints) {
      if (keypoint.confidence >= confidenceThreshold) {
        canvas.drawCircle(keypoint.position, 5.0, jointPaint);
      }
    }

    for (var edge in edges) {
      final p1 = _findKeypointByName(edge[0]);
      final p2 = _findKeypointByName(edge[1]);

      if (p1 != null &&
          p2 != null &&
          p1.confidence >= confidenceThreshold &&
          p2.confidence >= confidenceThreshold) {
        canvas.drawLine(p1.position, p2.position, paint);
      }
    }
  }

  PoseKeypoint? _findKeypointByName(String name) {
    try {
      return keypoints.firstWhere((kp) => kp.name == name);
    } catch (e) {
      return null;
    }
  }

  @override
  bool shouldRepaint(covariant PoseSkeletonPainter oldDelegate) {
    return oldDelegate.keypoints != keypoints ||
        oldDelegate.personBox != personBox ||
        oldDelegate.showSkeleton != showSkeleton;
  }
}
