import 'package:flutter/material.dart';
import 'package:another_flutter_splash_screen/another_flutter_splash_screen.dart';
import 'login.dart';

class SplashScreenPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FlutterSplashScreen.gif(
      gifPath: 'assets/juggling_splashscreen.gif',
      gifWidth: 269,
      gifHeight: 474,
      nextScreen: LoginPage(),
      duration: const Duration(milliseconds: 4100),
      onInit: () async {
        debugPrint("Splash Screen gestartet");
      },
      onEnd: () async {
        debugPrint("Splash Screen beendet");
      },
    );
  }
}
