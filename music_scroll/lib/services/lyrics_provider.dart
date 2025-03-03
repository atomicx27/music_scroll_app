// final String geniusAccessToken = "Vwqoaf4P028md9vae94xecUSLZsEwJe5SRg-0Pa9_93pecGagG2b3wu1hjl0gJau"; // Replace with your API Key
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class LyricsProvider {
  static const String _geniusAccessToken = "Vwqoaf4P028md9vae94xecUSLZsEwJe5SRg-0Pa9_93pecGagG2b3wu1hjl0gJau";

  Future<String?> getSongLyrics(String artist, String songTitle) async {
    try {
      print("🔍 Searching Genius for: $artist - $songTitle...");

      // Extract the first artist if multiple artists exist
      String primaryArtist = artist.split(",")[0].trim();

      List<String> searchQueries = [
        "$songTitle $primaryArtist", // Try song title + first artist
        songTitle // Try just the song title
      ];

      String? lyricsUrl;

      for (String query in searchQueries) {
        final searchUrl =
            "https://api.genius.com/search?q=${Uri.encodeComponent(query)}&access_token=$_geniusAccessToken";
        final response = await http.get(Uri.parse(searchUrl));

        if (response.statusCode != 200) {
          print("❌ Genius API Error: ${response.body}");
          return null;
        }

        final jsonResponse = json.decode(response.body);
        final hits = jsonResponse["response"]["hits"];

        if (hits.isNotEmpty) {
          final firstValidHit = hits.first;
          if (firstValidHit["result"]?["path"] != null) {
            lyricsUrl = "https://genius.com${firstValidHit["result"]["path"]}";
            break; // Stop searching if we find a valid result
          }
        }
      }

      if (lyricsUrl == null) {
        print("❌ No valid song result found.");
        return null;
      }

      print("🔗 Fetching lyrics from: $lyricsUrl");

      // Fetch and parse the entire lyrics page
      final lyricsPage = await http.get(Uri.parse(lyricsUrl));
      final document = parser.parse(lyricsPage.body);

      final lyricsContainers = document.querySelectorAll("div[data-lyrics-container]");
      if (lyricsContainers.isEmpty) {
        print("❌ Couldn't find lyrics on the page.");
        return null;
      }

      final lyrics = lyricsContainers.map((e) => e.text.trim()).join("\n");

      if (lyrics.isEmpty) {
        print("❌ No lyrics extracted.");
        return null;
      }

      print("✅ Lyrics fetched!");
      return lyrics;
    } catch (e) {
      print("⚠️ Error fetching lyrics: $e");
      return null;
    }
  }

}
