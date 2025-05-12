import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class CameraMoveNetPage extends StatefulWidget {
  @override
  _CameraMoveNetPageState createState() => _CameraMoveNetPageState();
}

class _CameraMoveNetPageState extends State<CameraMoveNetPage> {
  late CameraController _cameraController;
  tfl.Interpreter? _interpreter;
  bool isDetecting = false;
  bool isReady = false;
  bool isCameraRunning = false;
  bool isCountingJuggles = false;
  bool showHint = true;

  List<Offset> keypoints = [];
  List<List<Offset>> keypointsHistory = [];
  int juggleCount = 0;
  int highScore = 0;
  int currentStreak = 0;
  int bestStreak = 0;

  Offset? ballPosition;
  List<Offset> ballTrajectory = [];

  double? lastLeftFootY;
  double? lastRightFootY;
  List<double> leftFootHistory = [];
  List<double> rightFootHistory = [];
  bool isLeftFootMovingUp = false;
  bool isRightFootMovingUp = false;
  bool isLeftKickPending = false;
  bool isRightKickPending = false;

  final double movementThreshold = 0.005;
  final double kickThreshold = 0.006;
  final double confidenceThreshold = 0.2;
  final int historySize = 3;
  final Duration kickCooldown = Duration(milliseconds: 400);
  DateTime lastKickTime = DateTime.now();

  Color kickColor = Colors.white;
  double kickIndicatorSize = 0.0;

  Map<String, int> kicksByBodyPart = {
    'leftFoot': 0,
    'rightFoot': 0,
    'knee': 0,
    'head': 0,
  };

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadModel();
    await _initCamera();
    setState(() => isReady = true);
  }

  Future<void> _loadModel() async {
    try {
      _interpreter =
          await tfl.Interpreter.fromAsset('assets/movenet_lightning.tflite');
      print("✅ MoveNet Modell geladen");
    } catch (e) {
      print("❌ Fehler beim Modell laden: $e");
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.low,
      enableAudio: false,
    );
    await _cameraController.initialize();
    if (mounted) {
      print("📷 Kamera initialisiert");
    }
  }

  void _startCameraStream() {
    if (!mounted || _interpreter == null || isCameraRunning) return;
    _cameraController.startImageStream(_processImage);
    setState(() {
      isCameraRunning = true;
      showHint = false;
    });
    print("📷 Kamera-Stream gestartet");
  }

  void _stopCameraStream() {
    if (!isCameraRunning) return;
    _cameraController.stopImageStream();
    setState(() {
      isCameraRunning = false;
      isCountingJuggles = false;
    });
    print("📷 Kamera-Stream gestoppt");
  }

  void _startJuggleCounting() {
    setState(() {
      isCountingJuggles = true;
      juggleCount = 0;
      currentStreak = 0;
      ballPosition = null;
      ballTrajectory = [];
      lastLeftFootY = null;
      lastRightFootY = null;
      leftFootHistory.clear();
      rightFootHistory.clear();
      isLeftFootMovingUp = false;
      isRightFootMovingUp = false;
      isLeftKickPending = false;
      isRightKickPending = false;
      kicksByBodyPart = {
        'leftFoot': 0,
        'rightFoot': 0,
        'knee': 0,
        'head': 0,
      };
    });

    print("🎮 Jonglier-Zählung gestartet");

    HapticFeedback.mediumImpact();
  }

  void _stopJuggleCounting() {
    setState(() {
      isCountingJuggles = false;
    });

    if (juggleCount > highScore) {
      highScore = juggleCount;
    }

    if (currentStreak > bestStreak) {
      bestStreak = currentStreak;
    }

    print("🎮 Jonglier-Zählung gestoppt");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dein Ergebnis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Du hast $juggleCount Juggles geschafft!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('Highscore: $highScore'),
            SizedBox(height: 8),
            Text('Beste Serie: $bestStreak'),
            SizedBox(height: 16),
            Text('Nach Körperteil:'),
            ..._buildKickStatistics(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Zurück'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startJuggleCounting();
            },
            child: Text('Neu starten'),
          ),
        ],
      ),
    );
  }

  void _processImage(CameraImage image) async {
    if (isDetecting || _interpreter == null || !mounted) return;
    isDetecting = true;

    try {
      final input = await _preprocessYUV420ToTensor(image);
      var output = List.generate(
          1,
          (_) => List.generate(
              1, (_) => List.generate(17, (_) => List.filled(3, 0.0))));

      _interpreter!.run(input, output);

      List<Offset> newKeypoints = [];
      List<double> confidences = [];

      for (var kp in output[0][0]) {
        newKeypoints.add(Offset(kp[0], kp[1]));
        confidences.add(kp[2]);
      }

      List<Offset> smoothedKeypoints =
          _smoothKeypoints(newKeypoints, confidences);

      if (isCountingJuggles && smoothedKeypoints.length >= 17) {
        final leftFoot = smoothedKeypoints[15];
        final rightFoot = smoothedKeypoints[16];
        final leftConf = confidences[15];
        final rightConf = confidences[16];

        print(
            "Left foot: y=${leftFoot.dy.toStringAsFixed(3)}, conf=${leftConf.toStringAsFixed(2)} | "
            "Right foot: y=${rightFoot.dy.toStringAsFixed(3)}, conf=${rightConf.toStringAsFixed(2)}");
      }

      setState(() {
        keypoints = smoothedKeypoints;

        keypointsHistory.add(smoothedKeypoints);
        if (keypointsHistory.length > historySize) {
          keypointsHistory.removeAt(0);
        }
      });

      if (isCountingJuggles) {
        _detectJuggle(smoothedKeypoints);
        _simulateBallPosition();
      }
    } catch (e) {
      print("❌ Fehler bei Inferenz: $e");
    }

    isDetecting = false;
  }

  Future<Uint8List> _preprocessYUV420ToTensor(CameraImage image) async {
    final int width = image.width;
    final int height = image.height;
    final Uint8List yBuffer = image.planes[0].bytes;
    final Uint8List uBuffer = image.planes[1].bytes;
    final Uint8List vBuffer = image.planes[2].bytes;

    final int size = 192 * 192 * 3;
    Uint8List tensor = Uint8List(size);
    int tensorIndex = 0;

    for (int y = 0; y < 192; y++) {
      for (int x = 0; x < 192; x++) {
        final srcX = (x * width / 192).floor();
        final srcY = (y * height / 192).floor();

        final int yIndex = srcY * image.planes[0].bytesPerRow + srcX;
        final int uvIndex =
            (srcY ~/ 2) * image.planes[1].bytesPerRow + (srcX ~/ 2);

        final int Y = yBuffer[yIndex];
        final int U = uBuffer[uvIndex];
        final int V = vBuffer[uvIndex];

        int R = (Y + 1.370705 * (V - 128)).clamp(0, 255).toInt();
        int G = (Y - 0.337633 * (U - 128) - 0.698001 * (V - 128))
            .clamp(0, 255)
            .toInt();
        int B = (Y + 1.732446 * (U - 128)).clamp(0, 255).toInt();

        tensor[tensorIndex++] = R;
        tensor[tensorIndex++] = G;
        tensor[tensorIndex++] = B;
      }
    }

    return tensor;
  }

  List<Offset> _smoothKeypoints(
      List<Offset> newKeypoints, List<double> confidences) {
    if (keypointsHistory.isEmpty) return newKeypoints;

    List<Offset> smoothedKeypoints = [];

    for (int i = 0; i < newKeypoints.length; i++) {
      double weight =
          confidences[i] > confidenceThreshold ? confidences[i] : 0.3;
      double complement = 1.0 - weight;

      double sumX = newKeypoints[i].dx * weight;
      double sumY = newKeypoints[i].dy * weight;
      double totalWeight = weight;

      int historyCount = keypointsHistory.length;
      for (int j = 0; j < historyCount; j++) {
        double historyWeight =
            complement * (1.0 - j / historyCount) / historyCount;
        sumX += keypointsHistory[historyCount - 1 - j][i].dx * historyWeight;
        sumY += keypointsHistory[historyCount - 1 - j][i].dy * historyWeight;
        totalWeight += historyWeight;
      }

      if (totalWeight > 0) {
        smoothedKeypoints.add(Offset(sumX / totalWeight, sumY / totalWeight));
      } else {
        smoothedKeypoints.add(newKeypoints[i]);
      }
    }

    return smoothedKeypoints;
  }

  void _detectJuggle(List<Offset> keypoints) {
    if (keypoints.length < 17) return;

    final leftFoot = keypoints[15];
    final rightFoot = keypoints[16];
    final leftKnee = keypoints[13];
    final rightKnee = keypoints[14];

    final leftLegLength = _distance(leftKnee, leftFoot);
    final rightLegLength = _distance(rightKnee, rightFoot);
    final avgLegLength = (leftLegLength + rightLegLength) / 2;

    final dynamicMovementThreshold =
        movementThreshold * math.min(1.0, avgLegLength * 5);
    final dynamicKickThreshold =
        kickThreshold * math.min(1.0, avgLegLength * 5);

    DateTime now = DateTime.now();
    bool cooldownPassed = now.difference(lastKickTime) > kickCooldown;

    leftFootHistory.add(leftFoot.dy);
    rightFootHistory.add(rightFoot.dy);

    if (leftFootHistory.length > 5) leftFootHistory.removeAt(0);
    if (rightFootHistory.length > 5) rightFootHistory.removeAt(0);

    bool isLeftFootVisible =
        _isKeypointVisible(15, keypoints, confidenceThreshold);
    bool isRightFootVisible =
        _isKeypointVisible(16, keypoints, confidenceThreshold);

    bool isLeftFootPositionValid = leftFoot.dy > 0.6;
    bool isRightFootPositionValid = rightFoot.dy > 0.6;

    if (leftFootHistory.length >= 3 &&
        isLeftFootVisible &&
        isLeftFootPositionValid) {
      double recentAvgMovement = 0;
      for (int i = 1; i < leftFootHistory.length; i++) {
        recentAvgMovement += leftFootHistory[i - 1] - leftFootHistory[i];
      }
      recentAvgMovement /= (leftFootHistory.length - 1);

      bool isMovementPlausible = true;
      if (recentAvgMovement > 0.15 || recentAvgMovement < -0.15) {
        isMovementPlausible = false;
      }

      if (recentAvgMovement > dynamicMovementThreshold &&
          !isLeftFootMovingUp &&
          isMovementPlausible) {
        isLeftFootMovingUp = true;
        isLeftKickPending = true;
        print(
            "👣 Linker Fuß beginnt Aufwärtsbewegung: ${recentAvgMovement.toStringAsFixed(5)} (Schwelle: ${dynamicMovementThreshold.toStringAsFixed(5)})");
      } else if (recentAvgMovement < -dynamicKickThreshold &&
          isLeftFootMovingUp &&
          isLeftKickPending &&
          cooldownPassed &&
          isMovementPlausible) {
        isLeftFootMovingUp = false;
        isLeftKickPending = false;
        _registerKick('leftFoot', leftFoot);
        double absThreshold = dynamicKickThreshold;
        print(
            "⚽ Linker Fuß Kick erkannt: ${recentAvgMovement.toStringAsFixed(5)} (Schwelle: -${absThreshold.toStringAsFixed(5)})");
      } else if (recentAvgMovement > -dynamicMovementThreshold / 2 &&
          recentAvgMovement < dynamicMovementThreshold / 2) {
        if (!isLeftFootMovingUp) {
          isLeftKickPending = false;
        }
      }

      double absMovement =
          (recentAvgMovement < 0) ? -recentAvgMovement : recentAvgMovement;
      if (absMovement > dynamicMovementThreshold * 2 &&
          cooldownPassed &&
          isMovementPlausible) {
        double velocityChange = 0;
        if (leftFootHistory.length >= 4) {
          double v1 = leftFootHistory[0] - leftFootHistory[1];
          double v2 = leftFootHistory[2] - leftFootHistory[3];
          velocityChange = v1 - v2;

          double absVelocityChange =
              (velocityChange < 0) ? -velocityChange : velocityChange;
          if (absVelocityChange > dynamicKickThreshold * 2) {
            isLeftFootMovingUp = false;
            isLeftKickPending = false;
            _registerKick('leftFoot', leftFoot);
            print(
                "⚡ Schneller linker Fuß Kick erkannt: Vel.Änderung ${velocityChange.toStringAsFixed(5)}");
          }
        }
      }
    }

    if (rightFootHistory.length >= 3 &&
        isRightFootVisible &&
        isRightFootPositionValid) {
      double recentAvgMovement = 0;
      for (int i = 1; i < rightFootHistory.length; i++) {
        recentAvgMovement += rightFootHistory[i - 1] - rightFootHistory[i];
      }
      recentAvgMovement /= (rightFootHistory.length - 1);

      bool isMovementPlausible = true;
      if (recentAvgMovement > 0.15 || recentAvgMovement < -0.15) {
        isMovementPlausible = false;
      }

      if (recentAvgMovement > dynamicMovementThreshold &&
          !isRightFootMovingUp &&
          isMovementPlausible) {
        isRightFootMovingUp = true;
        isRightKickPending = true;
        print(
            "👣 Rechter Fuß beginnt Aufwärtsbewegung: ${recentAvgMovement.toStringAsFixed(5)} (Schwelle: ${dynamicMovementThreshold.toStringAsFixed(5)})");
      } else if (recentAvgMovement < -dynamicKickThreshold &&
          isRightFootMovingUp &&
          isRightKickPending &&
          cooldownPassed &&
          isMovementPlausible) {
        isRightFootMovingUp = false;
        isRightKickPending = false;
        _registerKick('rightFoot', rightFoot);
        double absThreshold = dynamicKickThreshold;
        print(
            "⚽ Rechter Fuß Kick erkannt: ${recentAvgMovement.toStringAsFixed(5)} (Schwelle: -${absThreshold.toStringAsFixed(5)})");
      } else if (recentAvgMovement > -dynamicMovementThreshold / 2 &&
          recentAvgMovement < dynamicMovementThreshold / 2) {
        if (!isRightFootMovingUp) {
          isRightKickPending = false;
        }
      }

      double absMovement =
          (recentAvgMovement < 0) ? -recentAvgMovement : recentAvgMovement;
      if (absMovement > dynamicMovementThreshold * 2 &&
          cooldownPassed &&
          isMovementPlausible) {
        double velocityChange = 0;
        if (rightFootHistory.length >= 4) {
          double v1 = rightFootHistory[0] - rightFootHistory[1];
          double v2 = rightFootHistory[2] - rightFootHistory[3];
          velocityChange = v1 - v2;

          double absVelocityChange =
              (velocityChange < 0) ? -velocityChange : velocityChange;
          if (absVelocityChange > dynamicKickThreshold * 2) {
            isRightFootMovingUp = false;
            isRightKickPending = false;
            _registerKick('rightFoot', rightFoot);
            print(
                "⚡ Schneller rechter Fuß Kick erkannt: Vel.Änderung ${velocityChange.toStringAsFixed(5)}");
          }
        }
      }
    }

    lastLeftFootY = leftFoot.dy;
    lastRightFootY = rightFoot.dy;
  }

  bool _isKeypointVisible(
      int keypointIndex, List<Offset> keypoints, double minConfidence) {
    if (keypointIndex >= keypoints.length) return false;

    Offset point = keypoints[keypointIndex];
    return point.dx >= 0 && point.dx <= 1 && point.dy >= 0 && point.dy <= 1;
  }

  double _distance(Offset p1, Offset p2) {
    return math.sqrt(math.pow(p1.dx - p2.dx, 2) + math.pow(p1.dy - p2.dy, 2));
  }

  void _registerKick(String bodyPart, Offset position) {
    lastKickTime = DateTime.now();
    juggleCount++;
    currentStreak++;

    kicksByBodyPart[bodyPart] = (kicksByBodyPart[bodyPart] ?? 0) + 1;

    setState(() {
      kickColor = _getKickColor(bodyPart);
      kickIndicatorSize = 50.0;

      ballPosition = Offset(position.dx, position.dy - 0.15);
    });

    HapticFeedback.mediumImpact();

    print("⚽ Kick mit $bodyPart erkannt! Zähler: $juggleCount");

    Future.delayed(Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          kickIndicatorSize = 0.0;
        });
      }
    });
  }

  void _simulateBallPosition() {
    if (ballPosition == null) return;

    DateTime now = DateTime.now();
    double timeSinceKick = now.difference(lastKickTime).inMilliseconds / 1000.0;

    if (timeSinceKick < 1.2) {
      double verticalSpeed = 0.4 * (1.0 - timeSinceKick / 1.2);
      double newY = ballPosition!.dy - verticalSpeed;

      setState(() {
        ballPosition = Offset(ballPosition!.dx, newY);

        ballTrajectory.add(ballPosition!);
        if (ballTrajectory.length > 10) {
          ballTrajectory.removeAt(0);
        }
      });
    }
  }

  Color _getKickColor(String bodyPart) {
    switch (bodyPart) {
      case 'leftFoot':
        return Colors.blue;
      case 'rightFoot':
        return Colors.green;
      case 'knee':
        return Colors.yellow;
      case 'head':
        return Colors.red;
      default:
        return Colors.white;
    }
  }

  void _startSession() {
    _startCameraStream();
  }

  void _endSession() {
    _stopCameraStream();
    Navigator.of(context).pop();
  }

  List<Widget> _buildKickStatistics() {
    List<Widget> stats = [];
    kicksByBodyPart.forEach((bodyPart, count) {
      if (count > 0) {
        String partName = '';
        switch (bodyPart) {
          case 'leftFoot':
            partName = 'Linker Fuß';
            break;
          case 'rightFoot':
            partName = 'Rechter Fuß';
            break;
          case 'knee':
            partName = 'Knie';
            break;
          case 'head':
            partName = 'Kopf';
            break;
          default:
            partName = bodyPart;
        }

        stats.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(partName),
              Text('$count', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ));
      }
    });

    return stats;
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _interpreter?.close();

    super.dispose();
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isReady
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController),
                CustomPaint(painter: PosePainter(keypoints)),
                if (ballPosition != null)
                  Positioned(
                    left: ballPosition!.dx * MediaQuery.of(context).size.width -
                        15,
                    top: ballPosition!.dy * MediaQuery.of(context).size.height -
                        15,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 5,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (ballTrajectory.isNotEmpty)
                  CustomPaint(
                    painter: TrajectoryPainter(ballTrajectory),
                    size: Size.infinite,
                  ),
                if (kickIndicatorSize > 0)
                  Center(
                    child: Container(
                      width: kickIndicatorSize,
                      height: kickIndicatorSize,
                      decoration: BoxDecoration(
                        color: kickColor.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                if (showHint)
                  Container(
                    color: Colors.black.withOpacity(0.85),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "📱 Halte dein Handy im Hochformat\n🧍‍♂️ 2-3 Meter Abstand halten\n⚽ Ball vor deinen Füßen positionieren",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 24),
                          ),
                          SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _startSession,
                            child: Text("Start"),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 15),
                              textStyle: TextStyle(fontSize: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isCameraRunning)
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Juggles: $juggleCount",
                            style: TextStyle(
                                fontSize: 26,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 5),
                          Text(
                            "Highscore: $highScore",
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isCameraRunning)
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isCountingJuggles)
                            ElevatedButton.icon(
                              icon: Icon(Icons.play_arrow),
                              label: Text("Zählung starten"),
                              onPressed: _startJuggleCounting,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                            )
                          else
                            ElevatedButton.icon(
                              icon: Icon(Icons.stop),
                              label: Text("Zählung stoppen"),
                              onPressed: _stopJuggleCounting,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                            ),
                          SizedBox(height: 10),
                          ElevatedButton.icon(
                            icon: Icon(Icons.close),
                            label: Text("Beenden"),
                            onPressed: _endSession,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          : Center(child: CircularProgressIndicator()),
    );
  }
}

class PosePainter extends CustomPainter {
  final List<Offset> keypoints;
  PosePainter(this.keypoints);

  static const List<List<int>> edges = [
    [5, 7],
    [7, 9],
    [6, 8],
    [8, 10],
    [11, 13],
    [13, 15],
    [12, 14],
    [14, 16],
    [5, 6],
    [11, 12],
    [5, 11],
    [6, 12],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (keypoints.isEmpty) return;

    final dotPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 4.0;

    for (final point in keypoints) {
      final scaled = Offset(point.dx * size.width, point.dy * size.height);
      canvas.drawCircle(scaled, 6.0, dotPaint);
    }
    for (final edge in edges) {
      if (edge[0] < keypoints.length && edge[1] < keypoints.length) {
        final p1 = Offset(keypoints[edge[0]].dx * size.width,
            keypoints[edge[0]].dy * size.height);
        final p2 = Offset(keypoints[edge[1]].dx * size.width,
            keypoints[edge[1]].dy * size.height);
        canvas.drawLine(p1, p2, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TrajectoryPainter extends CustomPainter {
  final List<Offset> trajectory;

  TrajectoryPainter(this.trajectory);

  @override
  void paint(Canvas canvas, Size size) {
    // Zeichnung der Linie entfernt
    // Die Methode bleibt leer
  }

  @override
  bool shouldRepaint(covariant TrajectoryPainter oldDelegate) {
    return oldDelegate.trajectory != trajectory;
  }
}
