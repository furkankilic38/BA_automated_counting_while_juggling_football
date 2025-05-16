/// ===========================================
/// Autor: Furkan Kilic
/// Beschreibung: Scoreboard-Seite der Footy-App.
/// Zeigt Statistiken und Aufzeichnungen der Jonglierleistungen des Benutzers an.
/// ===========================================
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';

class ScoreboardPage extends StatefulWidget {
  const ScoreboardPage({super.key});

  @override
  _ScoreboardPageState createState() => _ScoreboardPageState();
}

class _ScoreboardPageState extends State<ScoreboardPage> {
  List<Map<String, dynamic>> detections = [];
  bool _isLoading = true;
  int _totalJuggles = 0;
  int _highestRecord = 0;
  double _averageJuggles = 0;

  @override
  void initState() {
    super.initState();
    _loadDetections();
  }

  Future<void> _loadDetections() async {
    setState(() {
      _isLoading = true;
    });

    final dbHelper = DatabaseHelper.instance;
    final results = await dbHelper.getAllJuggleCounts();

    int total = 0;
    int highest = 0;

    for (var detection in results) {
      int count = detection['count'] as int;
      total += count;
      if (count > highest) highest = count;
    }

    setState(() {
      detections = results;
      _totalJuggles = total;
      _highestRecord = highest;
      _averageJuggles = results.isEmpty ? 0 : total / results.length;
      _isLoading = false;
    });
  }

  String _formatDateTime(String timestamp) {
    try {
      DateTime dateTime = DateTime.parse(timestamp);
      return DateFormat('dd.MM.yyyy - HH:mm').format(dateTime);
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scoreboard'),
        backgroundColor: Colors.green.shade800,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadDetections,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: Colors.green.shade800))
          : Column(
              children: [
                _buildStatisticsPanel(),
                Expanded(
                  child: detections.isEmpty
                      ? _buildEmptyState()
                      : _buildJuggleList(),
                ),
              ],
            ),
    );
  }

  Widget _buildStatisticsPanel() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.green.shade800, Colors.green.shade600],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deine Statistiken',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard(
                title: 'Gesamt',
                value: '$_totalJuggles',
                icon: Icons.sports_soccer,
              ),
              _buildStatCard(
                title: 'Rekord',
                value: '$_highestRecord',
                icon: Icons.emoji_events,
              ),
              _buildStatCard(
                title: 'Durchschnitt',
                value: _averageJuggles.toStringAsFixed(1),
                icon: Icons.equalizer,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      width: 100,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sports_soccer,
            size: 80,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: 20),
          Text(
            'Keine Jonglier-Einträge vorhanden',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Starte eine Jonglier-Session, um Statistiken zu sammeln!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildJuggleList() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView.builder(
        itemCount: detections.length,
        itemBuilder: (context, index) {
          final detection = detections[index];
          final juggleCount = detection['count'] as int;
          final isHighScore = juggleCount == _highestRecord;

          return Container(
            margin: EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
              border: isHighScore
                  ? Border.all(color: Colors.amber, width: 2)
                  : null,
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor:
                    isHighScore ? Colors.amber : Colors.green.shade100,
                child: Icon(
                  isHighScore ? Icons.emoji_events : Icons.sports_soccer,
                  color: isHighScore ? Colors.white : Colors.green.shade800,
                ),
              ),
              title: Row(
                children: [
                  Text(
                    '$juggleCount Juggles',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (isHighScore) ...[
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'REKORD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                _formatDateTime(detection['timestamp']),
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {},
            ),
          );
        },
      ),
    );
  }
}
