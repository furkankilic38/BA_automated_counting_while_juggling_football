import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:camera/camera.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../database_helper.dart';
import '../homepage.dart';
import 'camerapage.dart';
import 'juggle_counter_page.dart';
import '../scoreboard.dart';
import '../profile.dart';

class DetectedObject {
  final String tag;
  final List<double> box;
  DetectedObject({required this.tag, required this.box});
}

img.Image convertYUV420ToImage(CameraImage image) {
  final int width = image.width;
  final int height = image.height;
  final img.Image rgbImage = img.Image(width, height);

  final planeY = image.planes[0];
  final planeU = image.planes[1];
  final planeV = image.planes[2];

  for (int y = 0; y < height; y++) {
    final int uvRow = y ~/ 2;
    for (int x = 0; x < width; x++) {
      final int uvCol = x ~/ 2;
      final int indexY = y * planeY.bytesPerRow + x;
      final int indexU = uvRow * planeU.bytesPerRow + uvCol;
      final int indexV = uvRow * planeV.bytesPerRow + uvCol;
      final int yValue = planeY.bytes[indexY];
      final int uValue = planeU.bytes[indexU];
      final int vValue = planeV.bytes[indexV];

      double Y = yValue.toDouble();
      double U = uValue.toDouble() - 128;
      double V = vValue.toDouble() - 128;

      int R = (Y + 1.370705 * V).round();
      int G = (Y - 0.337633 * U - 0.698001 * V).round();
      int B = (Y + 1.732446 * U).round();

      R = R.clamp(0, 255);
      G = G.clamp(0, 255);
      B = B.clamp(0, 255);

      rgbImage.setPixelRgba(x, y, R, G, B, 255);
    }
  }
  return rgbImage;
}

List<Widget> displayBoundingBoxes(
    Size screen, List<dynamic> yoloResults, CameraImage? cameraImage) {
  if (yoloResults.isEmpty || cameraImage == null) return [];

  double factorX = screen.width / cameraImage.height.toDouble();
  double factorY = screen.height / cameraImage.width.toDouble();

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
          border: Border.all(color: Colors.green, width: 2),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            "$label ($confidence%)",
            style: TextStyle(
                color: Colors.white,
                backgroundColor: Colors.black,
                fontSize: 12),
          ),
        ),
      ),
    );
  }).toList();
}

class YOLODetection extends StatefulWidget {
  @override
  _YOLODetectionState createState() => _YOLODetectionState();
}

class _YOLODetectionState extends State<YOLODetection> {
  late CameraController controller;
  late FlutterVision vision;
  List<dynamic> yoloResults = [];
  late List<CameraDescription> cameras;
  CameraImage? cameraImage;

  bool isDetecting = false;
  bool isLoaded = false;
  bool isProcessing = false;
  bool isInitializing = true;
  int juggleCount = 0;

  List<double>? trackedPerson;

  List<double>? trackedBall;
  bool trackingStarted = false;

  List<dynamic> detectedObjects = [];

  Interpreter? _poseInterpreter;
  bool _isPoseModelLoaded = false;
  static const int inputImageSize = 192;

  double? _cameraWidth;
  double? _cameraHeight;

  int _selectedIndex = 0;

  List<Offset> poseKeypoints = [];

  @override
  void initState() {
    super.initState();
    initCamera();
    loadPoseModel();
  }

  Future<void> initCamera() async {
    try {
      cameras = await availableCameras();
      controller = CameraController(cameras[0], ResolutionPreset.medium,
          enableAudio: false);
      await controller.initialize();
      vision = FlutterVision();
      await vision.loadYoloModel(
        labels: 'assets/labels.txt',
        modelPath: 'assets/yolov8n_int8.tflite',
        modelVersion: 'yolov8',
        useGpu: false,
      );
      setState(() {
        isLoaded = true;
        isInitializing = false;
      });
      debugPrint("Camera initialized, YOLO model loaded.");
      startDetection();
    } catch (e) {
      debugPrint("Error during initialization: $e");
    }
  }

  Future<void> loadPoseModel() async {
    try {
      _poseInterpreter =
          await Interpreter.fromAsset('assets/movenet_lightning.tflite');
      setState(() {
        _isPoseModelLoaded = true;
      });
      debugPrint("Pose model loaded.");
    } catch (e) {
      debugPrint("Error loading pose model: $e");
    }
  }

  Future<void> startDetection() async {
    if (!controller.value.isInitialized) return;
    setState(() {
      isDetecting = true;
      juggleCount = 0;
      yoloResults.clear();
      detectedObjects.clear();
      trackedPerson = null;
      trackedBall = null;
      trackingStarted = false;
      poseKeypoints.clear();
    });
    await controller.startImageStream((image) async {
      if (_cameraWidth == null || _cameraHeight == null) {
        _cameraWidth = image.width.toDouble();
        _cameraHeight = image.height.toDouble();
        debugPrint("Camera dimensions set: $_cameraWidth x $_cameraHeight");
      }
      cameraImage = image;
      if (!isProcessing) {
        isProcessing = true;
        await runYoloDetection(image);

        bool runPose = yoloResults.any((result) =>
            result['tag'] == 'person' ||
            result['tag'] == 'sports ball' ||
            result['tag'] == 'football');
        if (runPose && _isPoseModelLoaded && trackedPerson != null) {
          debugPrint("Target object detected; running pose inference.");
          await runPoseDetection(image);
        } else {
          debugPrint("No target object for pose detection; skipping.");
        }
        isProcessing = false;
      }
    });
  }

  Future<void> stopDetection() async {
    setState(() {
      isDetecting = false;
      yoloResults.clear();
      detectedObjects.clear();
      trackedPerson = null;
      trackedBall = null;
      trackingStarted = false;
      poseKeypoints.clear();
    });
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
      debugPrint("Image stream stopped.");
    }
  }

  Future<void> runYoloDetection(CameraImage image) async {
    try {
      final result = await vision.yoloOnFrame(
          bytesList: image.planes.map((plane) => plane.bytes).toList(),
          imageHeight: image.height,
          imageWidth: image.width,
          iouThreshold: 0.3,
          confThreshold: 0.3,
          classThreshold: 0.3);
      debugPrint("YOLO result: $result");
      setState(() {
        yoloResults = result;
      });
      List<DetectedObject> tempObjects = [];
      for (var res in result) {
        if (res.containsKey('tag') && res.containsKey('box')) {
          tempObjects.add(DetectedObject(
            tag: res['tag'],
            box: List<double>.from(res['box']),
          ));
          debugPrint("Detected ${res['tag']} with box: ${res['box']}");
        }
      }
      setState(() {
        detectedObjects = tempObjects;
      });

      for (var obj in detectedObjects) {
        if (obj.tag == 'person' && trackedPerson == null) {
          trackedPerson = obj.box;
        }
        if ((obj.tag == 'sports ball' || obj.tag == 'football') &&
            trackedBall == null) {
          trackedBall = obj.box;
        }
      }
    } catch (e) {
      debugPrint("Error processing YOLO results: $e");
    }
  }

  Future<void> runPoseDetection(CameraImage image) async {
    if (_poseInterpreter == null || trackedPerson == null) return;
    try {
      img.Image fullRgb = convertYUV420ToImage(image);
      int x = trackedPerson![0].round();
      int y = trackedPerson![1].round();
      int w = (trackedPerson![2] - trackedPerson![0]).round();
      int h = (trackedPerson![3] - trackedPerson![1]).round();
      x = x.clamp(0, fullRgb.width - 1);
      y = y.clamp(0, fullRgb.height - 1);
      if (x + w > fullRgb.width) w = fullRgb.width - x;
      if (y + h > fullRgb.height) h = fullRgb.height - y;
      img.Image cropped = img.copyCrop(fullRgb, x, y, w, h);
      debugPrint("Cropped image to person box: x=$x, y=$y, w=$w, h=$h");
      img.Image resized = img.copyResize(cropped,
          width: inputImageSize, height: inputImageSize);
      List<List<List<List<int>>>> inputTensor = imageTo4DTensor(resized);
      List<List<List<List<double>>>> output = List.generate(
        1,
        (_) => List.generate(
          1,
          (_) => List.generate(
            17,
            (_) => List.filled(3, 0.0, growable: false),
            growable: false,
          ),
          growable: false,
        ),
        growable: false,
      );
      _poseInterpreter?.run(inputTensor, output);
      List<double> flatOutput = [];
      for (int i = 0; i < 1; i++) {
        for (int j = 0; j < 1; j++) {
          for (int k = 0; k < 17; k++) {
            flatOutput.addAll(output[i][j][k]);
          }
        }
      }
      debugPrint("Pose raw output (flattened): $flatOutput");
      List<Offset> kp = parsePoseOutput(flatOutput);

      double scaleX = w / inputImageSize;
      double scaleY = h / inputImageSize;
      kp = kp.map((p) => Offset(p.dx * scaleX + x, p.dy * scaleY + y)).toList();
      setState(() {
        poseKeypoints = kp;
      });
    } catch (e) {
      debugPrint("Error in pose detection: $e");
    }
  }

  List<List<List<List<int>>>> imageTo4DTensor(img.Image image) {
    int height = image.height;
    int width = image.width;
    List<List<List<List<int>>>> tensor = List.generate(
      1,
      (_) => List.generate(
        height,
        (y) => List.generate(
          width,
          (x) {
            int pixel = image.getPixel(x, y);
            return [img.getRed(pixel), img.getGreen(pixel), img.getBlue(pixel)];
          },
          growable: false,
        ),
        growable: false,
      ),
      growable: false,
    );
    return tensor;
  }

  List<Offset> parsePoseOutput(List<double> rawData) {
    List<Offset> keypoints = [];
    for (int i = 0; i < 17; i++) {
      double y = rawData[i * 3];
      double x = rawData[i * 3 + 1];
      keypoints.add(Offset(x * inputImageSize, y * inputImageSize));
    }
    return keypoints;
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    stopDetection();
    Widget nextPage;
    switch (index) {
      case 0:
        nextPage = HomePage();
        break;
      case 1:
        nextPage = CameraMoveNetPage();
        break;
      case 2:
        nextPage = ScoreboardPage();
        break;
      case 3:
        nextPage = ProfilePage();
        break;
      case 4:
        nextPage = JuggleCounterPage();
        break;
      default:
        nextPage = HomePage();
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => nextPage),
    );
  }

  @override
  void dispose() {
    if (controller.value.isStreamingImages) {
      controller.stopImageStream();
    }
    _poseInterpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          isInitializing
              ? Center(child: CircularProgressIndicator())
              : CameraPreview(controller),
          ...displayBoundingBoxes(
              MediaQuery.of(context).size, yoloResults, cameraImage),
          CustomPaint(
            painter: SkeletonPainter(
                poseKeypoints: poseKeypoints, trackedPerson: trackedPerson),
            child: Container(),
          ),
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: Text(
              'Juggles: $juggleCount',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: isDetecting ? stopDetection : startDetection,
              child: Text(isDetecting ? 'Stop Detection' : 'Start Detection'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.add_circle), label: 'New Entry'),
          BottomNavigationBarItem(
              icon: Icon(Icons.scoreboard), label: 'Scoreboard'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(
              icon: Icon(Icons.sports_soccer), label: 'Football Counter'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}

class SkeletonPainter extends CustomPainter {
  final List<Offset> poseKeypoints;
  final List<double>? trackedPerson;

  SkeletonPainter({required this.poseKeypoints, required this.trackedPerson});

  static const List<List<int>> poseEdges = [
    [5, 7],
    [7, 9],
    [6, 8],
    [8, 10],
    [5, 6],
    [5, 11],
    [6, 12],
    [11, 13],
    [13, 15],
    [12, 14],
    [14, 16],
    [11, 12],
    [1, 3],
    [2, 4],
    [1, 2],
    [0, 1],
    [0, 2],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (trackedPerson == null) return;

    final double offsetX = trackedPerson![0];
    final double offsetY = trackedPerson![1];
    final double boxWidth = trackedPerson![2] - trackedPerson![0];
    final double boxHeight = trackedPerson![3] - trackedPerson![1];

    double scaleX = boxWidth / 192;
    double scaleY = boxHeight / 192;

    final kpPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (var kp in poseKeypoints) {
      final transformed =
          Offset(kp.dx * scaleX + offsetX, kp.dy * scaleY + offsetY);
      canvas.drawCircle(transformed, 3.0, kpPaint);
    }

    for (var edge in poseEdges) {
      if (edge[0] < poseKeypoints.length && edge[1] < poseKeypoints.length) {
        final p1 = poseKeypoints[edge[0]];
        final p2 = poseKeypoints[edge[1]];
        final t1 = Offset(p1.dx * scaleX + offsetX, p1.dy * scaleY + offsetY);
        final t2 = Offset(p2.dx * scaleX + offsetX, p2.dy * scaleY + offsetY);
        canvas.drawLine(t1, t2, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter oldDelegate) {
    return oldDelegate.poseKeypoints != poseKeypoints ||
        oldDelegate.trackedPerson != trackedPerson;
  }
}
