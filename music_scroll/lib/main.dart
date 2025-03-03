import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'services/lyrics_provider.dart'; // Import the LyricsProvider class
import 'dart:async'; // For managing asynchronous operations
import 'dart:io'; // For file handling (storing downloaded songs)
import 'package:permission_handler/permission_handler.dart'; // For requesting storage permissions
import 'package:path/path.dart'; // For handling file paths
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';





void main() {
  runApp(MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Music App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Music App")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChangeNotifierProvider(
                    create: (context) => MusicScrollScreenProvider(),
                    child: MusicScrollScreen(),
                  ),
                ),
              ),
              child: Text("Play Random Songs"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DatasetMusicScreen(),
                ),
              ),
              child: Text("Play from Dataset"),
            ),
          ],
        ),
      ),
    );
  }
}

class DatasetMusicScreen extends StatefulWidget {
  const DatasetMusicScreen({super.key});

  @override
  _DatasetMusicScreenState createState() => _DatasetMusicScreenState();
}

class _DatasetMusicScreenState extends State<DatasetMusicScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<List<String>> _datasetSongs = [];
  final YoutubeExplode _yt = YoutubeExplode();
  final LyricsProvider lyricsProvider = LyricsProvider();
  int _currentIndex = 0;  // Track the current song index
  Map<int, String> _downloadedSongs = {};  // Stores downloaded file paths by index
  final String _downloadPath = "/storage/emulated/0/Music"; // Adjust for your platform
  Map<int, double> _downloadProgress = {};  // Track download progress per song
  Set<int> _downloadingIndexes = {};  // Track currently downloading songs
  bool _isLoadingCSV = false;
  bool _isSearchingYoutube = false;
  bool _isLoadingLyrics = false;
  String? _currentSongTitle;
  String? _currentArtist;
  String _errorMessage = '';
  String? _lyrics;



  @override
  void initState() {
    super.initState();
    print("🟢 App Initialized - Loading CSV...");
    _loadCSV();

    _audioPlayer.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.idle ||
          playerState.processingState == ProcessingState.completed) {
        print("🔄 Audio Playback Completed - Ready for next song.");
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _yt.close();
    print("🔴 App Disposed - Resources Released.");
    super.dispose();
  }

  Future<void> _loadCSV() async {
    setState(() {
      _isLoadingCSV = true;
      _errorMessage = '';
    });

    try {
      print("📂 Loading CSV file...");
      final rawData = await rootBundle.loadString("assets/songs.csv");
      List<List<dynamic>> listData = const CsvToListConverter().convert(rawData);
      listData.removeAt(0);

      setState(() {
        _datasetSongs = listData.map((row) => [row[1].toString(), row[2].toString()]).toList();
        _datasetSongs.shuffle();
      });

      print("✅ CSV Loaded Successfully. Total Songs: ${_datasetSongs.length}");
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load songs.csv dataset.";
      });
      print("❌ Error loading CSV: $e");
    } finally {
      setState(() {
        _isLoadingCSV = false;
      });
    }
  }

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _datasetSongs.length) {
      print("⚠️ Invalid song index: $index");
      return;
    }

    _currentIndex = index;
    _currentSongTitle = _datasetSongs[index][0];
    _currentArtist = _datasetSongs[index][1];
    // ✅ Add haptic feedback when a new song starts playing
    HapticFeedback.heavyImpact();

    print("▶️ Playing Song: $_currentSongTitle - $_currentArtist (Index: $_currentIndex)");

    setState(() {
      _isSearchingYoutube = true;
      _errorMessage = '';
      _lyrics = null;
    });

    try {
      if (_downloadedSongs.containsKey(index)) {
        print("📁 Playing from downloaded file...");
        String filePath = _downloadedSongs[index]!;
        await _audioPlayer.setFilePath(filePath);
      } else {
        print("🔍 Searching YouTube for: $_currentSongTitle $_currentArtist");
        final searchQuery = "$_currentSongTitle $_currentArtist";
        final searchResults = await _yt.search.getVideos(searchQuery);

        if (searchResults.isEmpty) throw Exception("No YouTube results found");

        final video = searchResults.first;
        final manifest = await _yt.videos.streamsClient.getManifest(video.id);
        final audioStream = manifest.audioOnly.withHighestBitrate();

        final freshUrl = Uri.parse(audioStream.url.toString()).replace(scheme: "https").toString();
        print("🎵 Streaming from URL: $freshUrl");

        await _audioPlayer.setUrl(freshUrl);
      }

      await _audioPlayer.play();
      print("✅ Playback started.");
    } catch (e) {
      setState(() => _errorMessage = "Error playing song: $e");
      print("❌ Error playing song: $e");
    } finally {
      setState(() => _isSearchingYoutube = false);
    }
  }

  Future<void> _manageDownloads() async {
    print("📥 Managing Downloads...");

    for (int i = _currentIndex + 1; i <= _currentIndex + 5 && i < _datasetSongs.length; i++) {
      if (!_downloadedSongs.containsKey(i)) {
        print("⬇️ Downloading next song at index: $i");
        await _downloadSong(i);
      }
    }

    // Remove outdated downloads (free up space)
    if (_currentIndex >= 5) {
      int oldIndex = _currentIndex - 3;
      if (_downloadedSongs.containsKey(oldIndex)) {
        print("🗑 Deleting old downloaded song at index: $oldIndex");
        File(_downloadedSongs[oldIndex]!).delete();
        _downloadedSongs.remove(oldIndex);
      }
    }
  }

  Future<void> _downloadSong(int index) async {
    if (_downloadedSongs.containsKey(index) || _downloadingIndexes.contains(index)) {
      return;
    }

    setState(() {
      _downloadingIndexes.add(index);
      _downloadProgress[index] = 0.0;  // Initialize progress at 0%
    });

    try {
      final songTitle = _datasetSongs[index][0];
      final artist = _datasetSongs[index][1];
      final searchQuery = "$songTitle $artist";

      final searchResults = await _yt.search.getVideos(searchQuery);
      if (searchResults.isEmpty) throw Exception("No YouTube results found");

      final video = searchResults.first;
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      final audioStream = manifest.audioOnly.withHighestBitrate();
      final freshUrl = Uri.parse(audioStream.url.toString()).replace(scheme: "https").toString();

      final directory = Directory(_downloadPath);
      if (!await directory.exists()) await directory.create(recursive: true);
      final filePath = "${directory.path}/$songTitle.mp3";
      final file = File(filePath);

      // Use streaming download with progress tracking
      final request = await http.Client().send(http.Request("GET", Uri.parse(freshUrl)));
      final totalBytes = request.contentLength ?? 1;
      int receivedBytes = 0;

      final sink = file.openWrite();
      await for (var chunk in request.stream) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        setState(() {
          _downloadProgress[index] = receivedBytes / totalBytes;  // Update percentage
        });
      }
      await sink.close();

      _downloadedSongs[index] = filePath;
    } catch (e) {
      print("❌ Download failed: $e");
    } finally {
      setState(() {
        _downloadingIndexes.remove(index);
        _downloadProgress.remove(index);  // Remove from tracking after completion
      });
    }
  }

  void _showDownloadStatusDialog() {
    showDialog(
      context: this.context, // 👈 Use `this.context` if inside a StatefulWidget
      builder: (BuildContext dialogContext) { // 👈 Explicit type
        return AlertDialog(
          title: Text("Upcoming Downloads"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (i) {
              int index = _currentIndex + i + 1;
              if (index >= _datasetSongs.length) return SizedBox();  // Skip if out of range

              String title = _datasetSongs[index][0];
              String artist = _datasetSongs[index][1];
              bool isDownloading = _downloadingIndexes.contains(index);
              bool isDownloaded = _downloadedSongs.containsKey(index);
              double progress = _downloadProgress[index] ?? 0.0;

              return ListTile(
                title: Text("$title - $artist"),
                trailing: isDownloading
                    ? CircularProgressIndicator(value: progress)  // Show progress
                    : isDownloaded
                    ? Icon(Icons.download_done, color: Colors.green)  // ✔ Downloaded
                    : Icon(Icons.download, color: Colors.grey),  // Not downloaded
              );
            }),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text("Close")),
          ],
        );
      },
    );
  }

  Future<void> _fetchLyrics(BuildContext context, String? artist, String? title) async {
    if (artist == null || title == null) {
      print("❌ Artist or title is null");
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Fetching Lyrics..."),
            ],
          ),
        ),
      );

      LyricsProvider lyricsProvider = LyricsProvider();
      String? lyrics = await lyricsProvider.getSongLyrics(artist, title);

      Navigator.of(context).pop(); // Close loading dialog

      if (lyrics != null && lyrics.isNotEmpty) {
        showDialog(
          context: context,
          builder: (lyricsContext) => AlertDialog(
            title: Text("$title - $artist"),
            content: SingleChildScrollView(child: Text(lyrics)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(lyricsContext).pop(),
                child: const Text("Close"),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (errorContext) => AlertDialog(
            title: const Text("No Lyrics Found"),
            content: const Text("Couldn't fetch lyrics for this song."),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(errorContext).pop(),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading if error occurs
      showDialog(
        context: context,
        builder: (errorContext) => AlertDialog(
          title: const Text("Error"),
          content: Text("Failed to fetch lyrics: $e"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(errorContext).pop(),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }









  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Dataset Songs")),
      body: Stack(
        children: [
          Column(
            children: [
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_currentSongTitle != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    "Now Playing: $_currentSongTitle - $_currentArtist",
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),

              /// 🔹 ADD BUTTONS HERE 🔹 ///
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      _fetchLyrics(context, _currentArtist, _currentSongTitle);
                    },
                    child: Text("Lyrics"),
                  ),
                  SizedBox(width: 10), // Space between buttons
                  ElevatedButton(
                    onPressed: _showDownloadStatusDialog,
                    child: Text("Download Status"),
                  ),
                ],
              ),

              Expanded(
                child: _isLoadingCSV
                    ? Center(child: CircularProgressIndicator())
                    : PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: _datasetSongs.length,
                  onPageChanged: (index) {
                    print("📜 Swiped to song at index: $index");
                    _playSong(index);
                    _manageDownloads();
                  },
                  itemBuilder: (context, index) {
                    return Center(
                      child: Text(
                        "${_datasetSongs[index][0]} - ${_datasetSongs[index][1]}",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          if (_isSearchingYoutube || _isLoadingCSV)
            Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}


class MusicScrollScreenProvider extends ChangeNotifier {
  final yt = YoutubeExplode();
  final AudioPlayer audioPlayer = AudioPlayer();
  bool isLoading = false;
  Video? currentVideo;
  List<Video> songs = [];
  String? currentSongTitle;
  String? errorMessage;
  String? lyrics;
  bool isLoadingLyrics = false;

  String selectedLanguage = "Both";
  String selectedYear = "Mix";
  String selectedMood = "Mix";

  final List<String> languages = ["Bollywood", "English", "Both"];
  final List<String> years = [
    "Mix",
    "1960s",
    "1970s",
    "1980s",
    "1990s",
    "2000s",
    "2010s",
    "2020s"
  ];
  final List<String> moods = ["Mix", "Happy", "Sad", "Energetic", "Relaxing"];

  final Map<String, List<Video>> _searchCache = {};
  final Map<String, String> _audioUrlCache = {};

  MusicScrollScreenProvider() {
    fetchSongs();
    audioPlayer.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.idle ||
          playerState.processingState == ProcessingState.completed) {
        currentSongTitle = null;
        currentVideo = null;
        lyrics = null;
        notifyListeners();
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    yt.close();
    super.dispose();
  }

  Future<List<Video>> _fetchYouTubeVideos(String query) async {
    if (_searchCache.containsKey(query)) {
      print("Fetching songs from cache for query: $query");
      return _searchCache[query]!;
    }

    print("Fetching songs from YouTube for query: $query");
    try {
      final searchResults = await compute(_performSearch, query);
      final videos = searchResults.take(30).toList();
      _searchCache[query] = videos;
      return videos;
    } catch (e) {
      errorMessage =
      "Error fetching songs from YouTube. Please check your connection.";
      print("Error fetching from YouTube: $e");
      return [];
    }
  }

  static Future<List<Video>> _performSearch(String query) async {
    final yt = YoutubeExplode();
    try {
      final searchResults = await yt.search.getVideos(query);
      yt.close();
      return searchResults.toList();
    } catch (e) {
      yt.close();
      rethrow;
    }
  }

  Future<String?> _getAudioUrl(Video video) async {
    final videoId = video.id.value;
    if (_audioUrlCache.containsKey(videoId)) {
      print("Fetching audio URL from cache for video: ${video.title}");
      return _audioUrlCache[videoId];
    }

    print("Fetching audio URL from YouTube for video: ${video.title}");
    try {
      final audioUrl = await compute(_performGetAudioUrl, videoId);
      if (audioUrl != null) {
        _audioUrlCache[videoId] = audioUrl;
      }
      return audioUrl;
    } catch (e) {
      errorMessage = "Error getting audio URL. Please try again.";
      print("Error getting audio URL: $e");
      return null;
    }
  }

  static Future<String?> _performGetAudioUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final audioStream = manifest.audioOnly.withHighestBitrate();
      yt.close();
      return audioStream.url.toString();
        } catch (e) {
      yt.close();
      rethrow;
    }
  }

  Future<void> fetchSongs() async {
    if (isLoading) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    String query = "top trending songs";
    if (selectedLanguage != "Both" ||
        selectedYear != "Mix" ||
        selectedMood != "Mix") {
      query = "";
      if (selectedLanguage != "Both") query += "$selectedLanguage ";
      if (selectedYear != "Mix") query += "$selectedYear ";
      if (selectedMood != "Mix") query += "$selectedMood ";
      query += "songs";
    }

    final searchResults = await _fetchYouTubeVideos(query);

    songs.clear();
    songs.addAll(searchResults);
    isLoading = false;
    notifyListeners();
  }

  Future<String?> fetchLyrics(String songTitle, String artist) async {
    isLoadingLyrics = true;
    lyrics = null;
    notifyListeners();
    print("Fetching lyrics for MusicScrollScreenProvider: Song: '$songTitle', Artist: '$artist'"); // Debug print
    try {
      final lyricsUri =
      Uri.parse('https://api.lyrics.ovh/v1/$artist/$songTitle');
      print("Lyrics API Request URL for MusicScrollScreenProvider: $lyricsUri"); // Debug print
      final response = await http.get(lyricsUri);
      print("Lyrics API Response Status Code for MusicScrollScreenProvider: ${response.statusCode}"); // Debug print
      print("Lyrics API Response Body for MusicScrollScreenProvider: ${response.body}"); // Debug print


      if (response.statusCode == 200) {
        final decodedResponse = jsonDecode(response.body);
        if (decodedResponse.containsKey('lyrics')) {
          lyrics = decodedResponse['lyrics'];
          return lyrics;
        } else {
          lyrics = "Lyrics not found.";
          return lyrics;
        }
      } else {
        lyrics = "Failed to fetch lyrics.";
        return lyrics;
      }
    } catch (e) {
      print("Error fetching lyrics: $e");
      lyrics = "Error fetching lyrics.";
      return lyrics;
    } finally {
      isLoadingLyrics = false;
      notifyListeners();
    }
  }

  Future<void> playSong(Video video) async {
    try {
      print("Playing song: ${video.title}");
      errorMessage = null;
      lyrics = null;
      final audioUrl = await _getAudioUrl(video);
      if (audioUrl != null) {
        await audioPlayer.setUrl(audioUrl);
        await audioPlayer.play();
        currentVideo = video;
        currentSongTitle = video.title;
        notifyListeners();
      } else {
        errorMessage = "Could not play: ${video.title}. Audio stream unavailable.";
        notifyListeners();
      }
    } catch (e) {
      errorMessage = "Error playing song: $e";
      print("Error playing song: $e");
      notifyListeners();
    }
  }

  Future<void> pauseSong() async {
    await audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stopSong() async {
    await audioPlayer.stop();
    currentVideo = null;
    currentSongTitle = null;
    lyrics = null;
    notifyListeners();
  }

  void setLanguageFilter(String language) {
    selectedLanguage = language;
    fetchSongs();
    notifyListeners();
  }

  void setYearFilter(String year) {
    selectedYear = year;
    fetchSongs();
    notifyListeners();
  }

  void setMoodFilter(String mood) {
    selectedMood = mood;
    fetchSongs();
    notifyListeners();
  }

  bool get isPlaying => audioPlayer.playerState.playing;
  bool get isBuffering => audioPlayer.playerState.processingState == ProcessingState.buffering;
}

class MusicScrollScreen extends StatelessWidget {
  const MusicScrollScreen({super.key});

  void _showLyricsBottomSheet(BuildContext context) {
    final musicProvider = Provider.of<MusicScrollScreenProvider>(context, listen: false);
    if (musicProvider.currentSongTitle == null) return;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Lyrics for: ${musicProvider.currentSongTitle}",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              musicProvider.isLoadingLyrics
                  ? Center(child: CircularProgressIndicator())
                  : (musicProvider.lyrics != null)
                  ? SingleChildScrollView(
                child: Text(
                  musicProvider.lyrics!,
                  style: TextStyle(fontSize: 16),
                ),
              )
                  : Text("Tap 'Get Lyrics' to fetch.", style: TextStyle(fontStyle: FontStyle.italic)),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicScrollScreenProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text("Random Songs")),
      body: Stack(
        children: [
          Column(
            children: [
              FilterDropdowns(),
              if (musicProvider.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    musicProvider.errorMessage!,
                    style: TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (musicProvider.currentSongTitle != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    "Now Playing: ${musicProvider.currentSongTitle}",
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: musicProvider.isLoading
                    ? Center(child: CircularProgressIndicator())
                    : musicProvider.songs.isEmpty && musicProvider.errorMessage == null
                    ? Center(child: Text("No songs found for selected filters."))
                    : PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: musicProvider.songs.length,
                  onPageChanged: (index) {
                    musicProvider.playSong(musicProvider.songs[index]);
                  },
                  itemBuilder: (context, index) {
                    return Center(
                      child: Text(
                        musicProvider.songs[index].title,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(musicProvider.isPlaying ? Icons.pause : Icons.play_arrow),
                      iconSize: 40,
                      onPressed: () {
                        if (musicProvider.isPlaying) {
                          musicProvider.pauseSong();
                        } else if (musicProvider.currentVideo != null) {
                          musicProvider.audioPlayer.play();
                        } else if (musicProvider.songs.isNotEmpty) {
                          musicProvider.playSong(musicProvider.songs.first);
                        }
                      },
                    ),
                    SizedBox(width: 20),
                    IconButton(
                      icon: Icon(Icons.stop),
                      iconSize: 40,
                      onPressed: musicProvider.stopSong,
                    ),
                    SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: (musicProvider.currentSongTitle != null)
                          ? () async {
                        await musicProvider.fetchLyrics(musicProvider.currentSongTitle!, musicProvider.currentVideo!.author);
                        _showLyricsBottomSheet(context);
                      }
                          : null,
                      child: Text("Get Lyrics"),
                    ),
                    if (musicProvider.isBuffering)
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.0)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (musicProvider.isLoading || musicProvider.isLoadingLyrics)
            Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class FilterDropdowns extends StatelessWidget {
  const FilterDropdowns({super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicScrollScreenProvider>(context);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          DropdownButton<String>(
            value: musicProvider.selectedLanguage,
            hint: Text("Language"),
            items: musicProvider.languages.map((String language) {
              return DropdownMenuItem<String>(
                value: language,
                child: Text(language),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                musicProvider.setLanguageFilter(newValue);
              }
            },
          ),
          DropdownButton<String>(
            value: musicProvider.selectedYear,
            hint: Text("Year"),
            items: musicProvider.years.map((String year) {
              return DropdownMenuItem<String>(
                value: year,
                child: Text(year),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                musicProvider.setYearFilter(newValue);
              }
            },
          ),
          DropdownButton<String>(
            value: musicProvider.selectedMood,
            hint: Text("Mood"),
            items: musicProvider.moods.map((String mood) {
              return DropdownMenuItem<String>(
                value: mood,
                child: Text(mood),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                musicProvider.setMoodFilter(newValue);
              }
            },
          ),
        ],
      ),
    );
  }
}
