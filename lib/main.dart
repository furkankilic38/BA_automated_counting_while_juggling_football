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
        '/': (context) => SplashScreenPage(),
        '/login': (context) => LoginPage(),
        '/home': (context) => HomePage(),
        '/enhanced_juggle': (context) => EnhancedJuggleCounterPage(),
      },
      debugShowCheckedModeBanner: false,
    ),
  );
}
