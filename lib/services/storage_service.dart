import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_link.dart';

/// Persists saved links and the user's folder list to on-device storage so
/// they survive app restarts. Folders are stored separately from links so
/// an empty folder (no links in it yet) is not silently lost.
class StorageService {
  static const _linksKey = 'content_library.saved_links.v1';
  static const _foldersKey = 'content_library.folders.v1';

  Future<List<SavedLink>> loadLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_linksKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return SavedLink.decodeList(raw);
    } catch (_) {
      // Corrupt data should never crash the app on launch.
      return [];
    }
  }

  Future<void> saveLinks(List<SavedLink> links) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_linksKey, SavedLink.encodeList(links));
  }

  Future<List<String>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_foldersKey) ?? [];
  }

  Future<void> saveFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_foldersKey, folders);
  }
}
