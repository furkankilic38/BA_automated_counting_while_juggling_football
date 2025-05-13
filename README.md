# BA_automated_counting_while_juggling_football
Bachelorarbeit "Automatisiertes Zählen beim Jonglieren eines Fußballs - von Furkan Kilic

Footballista ist eine prototypische mobile Anwendung, die mithilfe von maschinellem Lernen (ML) automatisch die Anzahl der Ballkontakte bei Fußball-Jonglierübungen erkennt und zählt. Sie wurde als Teil einer Bachelorarbeit entwickelt und dient als Proof-of-Concept zur Demonstration, wie moderne ML-Modelle (YOLOv8n und MoveNet-Lightning), in Echtzeit auf mobilen Geräten für die Erkennung von Ball und Spieler eingesetzt werden können.

## Funktionsumfang
- Echtzeit-Jongliererkennung: Zählt automatisch die Ballkontakte während des Jonglierens
- Live-VIsualisierung: Zeigt den Ball und die erkannte Person mit Bounding-Boxen und Keypoints an
- Statistik-Tracking: Speichert und zeigt die besten Ergebnisse und Durchschnittswerte an
- Benutzerprofil: Nutzer:innen können ihre Fortschritte über mehrere Sessions hinweg nachverfolgen.
- Plattform: Flutter (Dart) mit nativem Java-Backend

## Systemarchitektur
- Frontend: Flutter (Dart)
- Backend (Native ML): Java (Android)
- ML-Modelle: yolov8n_int8.tflite und movenet_lightning.tflite
- Kommunikation: MethodChannels für die Verbindung zwischen Flutter (Dart) und nativem Android-Code (Java)
- Datenbank: SQLite zur Speicherung der Jonglierergebnisse und Nutzerdaten

## Implementierungsdetails

### ML-Modelle
- YOLOv8 (Nano, int8): Wird für die Erkennung des Balls verwendet
- MoveNet (Lightning, float32): Erkennt die Körperpose der Person
- MethodChannels: Kommunikation zwischen Flutter und dem nativen Andoid-Teil, um Modelle aufzurufen und Ergebnisse zurückzugeben

### Datenbank
- SQLite: Speicherung der Ergebisse (Anzahl der Jonglierkontakte) und Nutzerdaten
- SharedPreferences: Speicherung der Benutzereinstellungen

### Nutzung der App:
- Nutzer:innen starten eine Jonglier-Session über die App
- Der Ball und die Pose werden in Echtzeit erkannt und gezählt
- Die Ergebnisse werden automatisch in der lokalen Datenbank gespeichert

## Ergebnisse und Optimierungen

- Die App erreicht eine durchschnittliche FPS von 10-15 auf modernen Geräten (Pixel 6).
- Die Erkennungsgenauigkeit für den Ball liegt bei ca. 85%.
- Optimierungen wie Frame-Skipping und asynchrone Verarbeitung verbessern die Performance.

## Entwicklungsumgebung

- Framework: Flutter (Dart) - Version 3.x
- Native Entwicklung: Android (Java)
- ML-Bibliotheken: TensorFlow Lite (TFLite) für YOLOv8 und MoveNet
- IDE: Visual Studio Code
- Testgeräte: Google Pixel 6 (Android), Samsung Galaxy A3 (Android)

## Installation und Nutzung

### Voraussetzungen

- Flutter SDK installiert (https://flutter.dev)
- Android SDK installiert (für Android)
- Visual Studio Code oder Android Studio

### Installation
#### Repository klonen

- git clone https://github.com/dein-username/footballista.git
- cd footballista

#### Abhängigkeiten installieren

- flutter pub get

#### App starten (für Android)

- flutter run

### Modelle hinzufügen

- Das Verzeichnis /assets/models/ enthält die ML-Modelle:
- yolov8n_int8.tflite für Ball-Erkennung
- movenet_lightning.tflite für Pose-Erkennung

### Nutzung

- App starten und registrieren
- Über die Startseite eine neue Jonglier-Session beginnen
- Das System zählt automatisch die Ballkontakte und zeigt die Ergebnisse an
- Ergebnisse können auf der Scoreboard-Seite eingesehen werden
