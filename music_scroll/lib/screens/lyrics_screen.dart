import 'package:flutter/material.dart';
import '../services/lyrics_service.dart';

class LyricsScreen extends StatefulWidget {
  final String songTitle;

  const LyricsScreen({super.key, required this.songTitle});

  @override
  _LyricsScreenState createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  String lyrics = "Fetching lyrics...";
  final LyricsService lyricsService = LyricsService();

  @override
  void initState() {
    super.initState();
    fetchLyrics();
  }

  void fetchLyrics() async {
    String? fetchedLyrics = await lyricsService.getSongLyrics(widget.songTitle);
    setState(() {
      lyrics = fetchedLyrics ?? "Lyrics not found.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.songTitle)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(lyrics, style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}
