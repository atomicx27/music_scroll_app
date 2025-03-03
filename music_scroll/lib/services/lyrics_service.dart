import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class LyricsService {
  final String geniusAccessToken = "YOUR_ACCESS_TOKEN"; // Replace with your actual token

  Future<String?> getSongLyrics(String songTitle) async {
    try {
      print("🔍 Searching Genius for: $songTitle...");

      // Step 1: Search for the song on Genius
      final searchUrl =
          "https://api.genius.com/search?q=${Uri.encodeComponent(songTitle)}&access_token=$geniusAccessToken";
      final response = await http.get(Uri.parse(searchUrl));

      if (response.statusCode != 200) {
        print("❌ Genius API Error: ${response.body}");
        return null;
      }

      final jsonResponse = json.decode(response.body);
      if (jsonResponse["response"]["hits"].isEmpty) {
        print("❌ No lyrics found.");
        return null;
      }

      // Step 2: Extract song URL from API response
      final songPath = jsonResponse["response"]["hits"][0]["result"]["path"];
      final lyricsUrl = "https://genius.com$songPath";
      print("🔗 Fetching lyrics from: $lyricsUrl");

      // Step 3: Scrape lyrics from the Genius page
      final lyricsPage = await http.get(Uri.parse(lyricsUrl));
      final document = parser.parse(lyricsPage.body);
      final lyricsElement = document.querySelector("div.lyrics") ??
          document.querySelector("div[data-lyrics-container]");

      if (lyricsElement == null) {
        print("❌ Couldn't find lyrics on the page.");
        return null;
      }

      // Step 4: Extract lyrics text
      final lyrics = lyricsElement.text.trim();
      print("✅ Lyrics found!");
      return lyrics;
    } catch (e) {
      print("⚠️ Error fetching lyrics: $e");
      return null;
    }
  }
}
