/// ===========================================
/// Autor: Furkan Kilic
/// Beschreibung: Database Helper für die Footy-App.
/// Stellt Funktionen zur Verwaltung der lokalen SQLite-Datenbank bereit,
/// inkl. Benutzerauthentifizierung und Speicherung von Erkennungsergebnissen.
/// ===========================================
library;

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_database.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        firstname TEXT,
        lastname TEXT,
        age INTEGER,
        footballteam TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE detections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        count INTEGER NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<int> addUser(Map<String, dynamic> user) async {
    final db = await instance.database;
    int result = await db.insert('users', user);
    print('User added: $user');
    return result;
  }

  Future<Map<String, dynamic>?> getUser(
      String username, String password) async {
    final db = await instance.database;

    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );

    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await instance.database;
    return await db.query('users');
  }

  Future<Map<String, dynamic>?> authenticateUser(
      String username, String password) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    print('Login attempt: username=$username, password=$password');
    print('Query result: $result');
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('lastUsername');

    if (username == null) {
      debugPrint("No username found in SharedPreferences.");
      return null;
    }

    final db = await database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );

    if (result.isNotEmpty) {
      debugPrint("User found: ${result.first}");
      return result.first;
    } else {
      debugPrint("No user found in database for username: $username");
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );

    if (result.isNotEmpty) {
      return result.first;
    } else {
      return null;
    }
  }

  Future<void> addLaptopDetection(int count) async {
    final db = await database;
    await db.insert(
      'detections',
      {
        'type': 'laptop',
        'count': count,
        'timestamp': DateTime.now().toIso8601String()
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAllLaptopDetections() async {
    final db = await database;
    return await db.query(
      'detections',
      where: 'type = ?',
      whereArgs: ['laptop'],
      orderBy: 'timestamp DESC',
    );
  }

  Future<void> addJuggleCount(int count) async {
    final db = await database;
    await db.insert(
      'detections',
      {
        'type': 'football',
        'count': count,
        'timestamp': DateTime.now().toIso8601String()
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAllJuggleCounts() async {
    final db = await database;
    return await db.query(
      'detections',
      where: 'type = ?',
      whereArgs: ['football'],
      orderBy: 'timestamp DESC',
    );
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
