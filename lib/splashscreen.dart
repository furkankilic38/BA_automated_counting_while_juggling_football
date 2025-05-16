/// ===========================================
/// Autor: Furkan Kilic
/// Beschreibung: Splashscreen der Footballista-App.
/// Zeigt einen animierten Ladebildschirm beim Start der App.
/// ===========================================
library;

import 'package:flutter/material.dart';
import 'package:another_flutter_splash_screen/another_flutter_splash_screen.dart';
import 'login.dart';

class SplashScreenPage extends StatelessWidget {
  const SplashScreenPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FlutterSplashScreen.gif(
      gifPath: 'assets/juggling_splashscreen.gif',
      gifWidth: 269,
      gifHeight: 474,
      nextScreen: const LoginPage(),
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
