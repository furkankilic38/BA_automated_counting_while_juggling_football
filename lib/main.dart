/// ===========================================
/// Autor: Furkan Kilic
/// Beschreibung: Haupteinstiegspunkt der Footballista-App.
/// Initialisiert die App, richtet die Datenbankverbindung ein und definiert
/// die wichtigsten Routen der Anwendung.
/// ===========================================
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'homepage.dart';
import 'login.dart';
import 'splashscreen.dart';
import 'database_helper.dart';
import 'enhanced_juggle_counter_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DatabaseHelper.instance.database;

  runApp(
    MaterialApp(
      title: 'Footballista',
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreenPage(),
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/enhanced_juggle': (context) => const EnhancedJuggleCounterPage(),
      },
      debugShowCheckedModeBanner: false,
    ),
  );
}
