import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'database_helper.dart';

class CameraPage extends StatefulWidget {
  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late CameraController _cameraController;
  late FlutterVision vision;
  bool _isDetecting = false;
  List<dynamic> _yoloResults = [];
  int _juggleCount = 0;
  double? _lastFootY;
  bool _ballContact = false;
  final double threshold = 30.0;
  final Duration cooldown = Duration(milliseconds: 400);
  DateTime _lastKickTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initModel();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    _cameraController = CameraController(cameras[0], ResolutionPreset.medium);
    await _cameraController.initialize();
    setState(() {});
    _cameraController.startImageStream(_processCameraImage);
  }

  Future<void> _initModel() async {
    vision = FlutterVision();
    await vision.loadYoloModel(
      modelPath: 'assets/yolov8n-pose_float16.tflite',
      labels: 'assets/labels.txt', // Falls du ein Labels-File brauchst, sonst leer lassen
      modelVersion: 'yolov8',
      useGpu: false,
    );
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;

    final results = await vision.yoloOnFrame(
      bytesList: image.planes.map((plane) => plane.bytes).toList(),
      imageHeight: image.height,
      imageWidth: image.width,
      iouThreshold: 0.3,
      confThreshold: 0.3,
      classThreshold: 0.3,
    );

    setState(() {
      _yoloResults = results;
    });

    _analyzePoses(results);

    _isDetecting = false;
  }

  void _analyzePoses(List<dynamic> results) {
    for (var res in results) {
      if (res['tag'] == 'person' && res.containsKey('keypoints')) {
        List keypoints = res['keypoints'];
        List<double> foot = keypoints[16]; // Rechtes Fußgelenk

        double footY = foot[1];
        if (_lastFootY != null) {
          double dy = _lastFootY! - footY;
          DateTime now = DateTime.now();
          if (dy > threshold && !_ballContact && now.difference(_lastKickTime) > cooldown) {
            setState(() {
              _juggleCount++;
              _ballContact = true;
              _lastKickTime = now;
            });
          } else if (dy < -threshold / 2) {
            _ballContact = false;
          }
        }
        _lastFootY = footY;
      }
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_cameraController.value.isInitialized)
            CameraPreview(_cameraController),
          CustomPaint(
            painter: PosePainter(_yoloResults),
            child: Container(),
          ),
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: Center(
              child: Text(
                "Juggles: $_juggleCount",
                style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                DatabaseHelper.instance.addJuggleCount(_juggleCount);
                Navigator.pop(context);
              },
              child: Text("Speichern & Zurück"),
            ),
          ),
        ],
      ),
    );
  }
}

class PosePainter extends CustomPainter {
  final List<dynamic> results;

  PosePainter(this.results);

  static const List<List<int>> edges = [
    [5, 7], [7, 9], // rechter Arm
    [6, 8], [8, 10], // linker Arm
    [11, 13], [13, 15], // rechtes Bein
    [12, 14], [14, 16], // linkes Bein
    [5, 6], // Schultern
    [11, 12], // Hüften
    [5, 11], // Körper rechts
    [6, 12], // Körper links
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.green..strokeWidth = 3.0;
    final dotPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;

    for (var res in results) {
      if (res.containsKey('keypoints')) {
        List keypoints = res['keypoints'];
        List<Offset> points = keypoints.map<Offset>((kp) {
          return Offset(kp[0].toDouble(), kp[1].toDouble());
        }).toList();

        // Punkte zeichnen
        for (final p in points) {
          canvas.drawCircle(p, 5.0, dotPaint);
        }

        // Linien zeichnen
        for (final edge in edges) {
          if (edge[0] < points.length && edge[1] < points.length) {
            canvas.drawLine(points[edge[0]], points[edge[1]], paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(PosePainter oldDelegate) => true;
}
