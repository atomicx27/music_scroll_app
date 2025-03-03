import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final Dio _dio = Dio();
  final Map<int, String> _downloadedSongs = {}; // Stores downloaded song paths

  Future<String?> downloadSong(int index, String url, String songId) async {
    try {
      Directory tempDir = await getTemporaryDirectory();
      String filePath = '${tempDir.path}/$songId.mp3';

      if (await File(filePath).exists()) {
        print('✅ Song already downloaded: $filePath');
        return filePath; // Return existing file path
      }

      print('📥 Downloading: $url');
      await _dio.download(url, filePath);

      _downloadedSongs[index] = filePath;
      print('✔️ Download complete: $filePath');
      return filePath;
    } catch (e) {
      print('❌ Error downloading song: $e');
      return null; // Return null if download fails
    }
  }

  Future<void> deleteSong(int index) async {
    if (_downloadedSongs.containsKey(index)) {
      String filePath = _downloadedSongs[index]!;
      File file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        print('🗑️ Deleted song: $filePath');
      }
      _downloadedSongs.remove(index);
    }
  }

  String? getDownloadedSongPath(int index) {
    return _downloadedSongs[index];
  }
}
