import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'dart:math';

class Vector2D {
  final double x;
  final double y;

  Vector2D(this.x, this.y);

  double magnitude() {
    return sqrt(x * x + y * y);
  }

  double angleTo(Vector2D other) {
    final dot = x * other.x + y * other.y;
    final mag1 = magnitude();
    final mag2 = other.magnitude();
    if (mag1 == 0 || mag2 == 0) return 0;
    return acos(dot / (mag1 * mag2)) * 180 / pi;
  }
}

class JuggleCounterPage extends StatefulWidget {
  @override
  _JuggleCounterPageState createState() => _JuggleCounterPageState();
}

class _JuggleCounterPageState extends State<JuggleCounterPage> {
  late CameraController controller;
  late FlutterVision vision;
  late List<dynamic> yoloResults;
  bool isDetecting = false;
  bool isLoaded = false;
  bool isProcessing = false;

  int contactCount = 0;
  Map<String, List<double>> trackedObjects = {};
  List<Offset> ballTrajectory = [];
  DateTime lastProcessingTime = DateTime.now();

  Offset? lastBallPosition;
  DateTime? lastBallContact;
  Vector2D? lastBallVector;

  static const int targetFPS = 15;
  static const Duration minProcessingInterval =
      Duration(milliseconds: 1000 ~/ targetFPS);

  static const double velocityThreshold = 30.0;
  static const double directionChangeThreshold = 45.0;
  static const Duration minContactInterval = Duration(milliseconds: 300);

  CameraImage? cameraImage;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      final cameras = await availableCameras();
      controller = CameraController(cameras[0], ResolutionPreset.low,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);

      vision = FlutterVision();
      await controller.initialize();
      await loadYOLOModel();

      setState(() {
        isLoaded = true;
        yoloResults = [];
      });
    } catch (e) {
      debugPrint("Initialization error: $e");
    }
  }

  Future<void> loadYOLOModel() async {
    try {
      await vision.loadYoloModel(
        labels: 'assets/labels.txt',
        modelPath: 'assets/yolov8n_int8.tflite',
        modelVersion: 'yolov8',
        useGpu: true,
      );
    } catch (e) {
      debugPrint("Model loading error: $e");
    }
  }

  Future<void> yoloOnFrame(CameraImage cameraImage) async {
    if (isProcessing) return;

    final now = DateTime.now();
    if (now.difference(lastProcessingTime) < minProcessingInterval) return;
    lastProcessingTime = now;

    isProcessing = true;

    try {
      final result = await vision.yoloOnFrame(
        bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
        imageHeight: cameraImage.height,
        imageWidth: cameraImage.width,
        iouThreshold: 0.3,
        confThreshold: 0.4,
        classThreshold: 0.4,
      );

      setState(() {
        yoloResults = result;
        _processDetections(cameraImage);
      });
    } catch (e) {
      debugPrint("YOLO processing error: $e");
    }

    isProcessing = false;
  }

  void _processDetections(CameraImage image) {
    final person = yoloResults.firstWhere(
      (item) => item['tag'] == 'person',
      orElse: () => {'tag': null, 'box': null},
    );

    final football = yoloResults.firstWhere(
      (item) => item['tag'] == 'football' || item['tag'] == 'sports ball',
      orElse: () => {'tag': null, 'box': null},
    );

    if (person['tag'] != null && football['tag'] != null) {
      trackedObjects['person'] = person['box'];
      trackedObjects['football'] = football['box'];

      final ballX = (football['box'][0] + football['box'][2]) / 2;
      final ballY = (football['box'][1] + football['box'][3]) / 2;
      final currentBallPosition = Offset(ballX, ballY);

      if (lastBallPosition != null) {
        final vector = Vector2D(currentBallPosition.dx - lastBallPosition!.dx,
            currentBallPosition.dy - lastBallPosition!.dy);

        if (lastBallVector != null) {
          final angle = vector.angleTo(lastBallVector!);
          final speed = vector.magnitude();

          if (angle > directionChangeThreshold &&
              speed > velocityThreshold &&
              (lastBallContact == null ||
                  DateTime.now().difference(lastBallContact!) >
                      minContactInterval)) {
            contactCount++;
            lastBallContact = DateTime.now();

            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Kontakt erkannt! Anzahl: $contactCount'),
                duration: Duration(milliseconds: 500),
              ),
            );
          }
        }

        lastBallVector = vector;
        ballTrajectory.add(currentBallPosition);

        if (ballTrajectory.length > 10) {
          ballTrajectory.removeAt(0);
        }
      }

      lastBallPosition = currentBallPosition;
    }

    if (football['tag'] != null) {
      final ballBottom = football['box'][3];
      if (ballBottom >= image.height.toDouble() - 10) {
        stopDetection();
      }
    }
  }

  List<Widget> displayBoundingBoxes(Size screen) {
    if (yoloResults.isEmpty || cameraImage == null) return [];
    double factorX = screen.width / (cameraImage?.height ?? 1);
    double factorY = screen.height / (cameraImage?.width ?? 1);
    Color colorPick = Colors.blue;

    return yoloResults.map((result) {
      final x = result['box'][0] * factorX;
      final y = result['box'][1] * factorY;
      final width = (result['box'][2] - result['box'][0]) * factorX;
      final height = (result['box'][3] - result['box'][1]) * factorY;
      final label = result['tag'];
      final confidence = (result['box'][4] * 100).toStringAsFixed(1);

      return Positioned(
        left: x,
        top: y,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            border: Border.all(color: colorPick, width: 2),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              "$label ($confidence%)",
              style: TextStyle(
                color: Colors.white,
                backgroundColor: colorPick,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Future<void> startDetection() async {
    setState(() {
      isDetecting = true;
      contactCount = 0;
    });

    if (controller.value.isStreamingImages) return;

    await controller.startImageStream((image) async {
      cameraImage = image;
      await yoloOnFrame(image);
    });
  }

  Future<void> stopDetection() async {
    setState(() {
      isDetecting = false;
      trackedObjects.clear();
    });

    await controller.stopImageStream();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Detection stopped. Total contacts: $contactCount')),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    vision.closeYoloModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: Text('Football Juggling Counter'),
        backgroundColor: Colors.blue,
      ),
      body: Stack(
        children: [
          if (isLoaded)
            CameraPreview(controller)
          else
            Center(child: CircularProgressIndicator()),
          ...displayBoundingBoxes(size),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Text(
                  'Contacts: $contactCount',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
                SizedBox(height: 10),
                ElevatedButton(
                  onPressed: isDetecting ? stopDetection : startDetection,
                  child:
                      Text(isDetecting ? 'Stop Detection' : 'Start Detection'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
