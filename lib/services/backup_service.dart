import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/saved_link.dart';

/// What a backup file contains once it has been read back.
class BackupData {
  const BackupData({required this.links, required this.folders});
  final List<SavedLink> links;
  final List<String> folders;
}

/// Creates and reads backup files (plain JSON, so they are easy to keep and
/// to inspect). Saving and picking use Android's system file dialogs through
/// a small native channel in MainActivity; nothing here needs a Google
/// account or internet access.
class BackupService {
  static const _channel = MethodChannel('reelbox/backup');
  static const _format = 'reelbox-backup';

  static String fileName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'reelbox-backup-${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}.json';
  }

  static String encode(List<SavedLink> links, List<String> folders) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'folders': folders,
      'links': links.map((e) => e.toJson()..remove('thumbnailFile')).toList(),
    });
  }

  /// Opens the system "save as" dialog. Returns true if a file was written,
  /// false if the user cancelled.
  static Future<bool> saveToDevice(List<SavedLink> links, List<String> folders) async {
    final bytes = Uint8List.fromList(utf8.encode(encode(links, folders)));
    final ok = await _channel.invokeMethod<bool>('save', {
      'name': fileName(),
      'bytes': bytes,
    });
    return ok == true;
  }

  /// Opens the normal share sheet with the backup attached, so it can be
  /// sent to Gmail, Telegram, Google Drive, etc.
  static Future<void> share(List<SavedLink> links, List<String> folders) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${fileName()}');
    await file.writeAsString(encode(links, folders));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Reelbox backup',
      ),
    );
  }

  /// Opens the system file picker and returns the chosen file's text, or
  /// null if the user cancelled.
  static Future<String?> pickBackupText() => _channel.invokeMethod<String>('open');

  /// Returns null if [text] is not a valid Reelbox backup.
  static BackupData? parse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      final rawLinks = decoded['links'];
      if (rawLinks is! List) return null;
      final links = rawLinks
          .map((e) => SavedLink.fromJson(e as Map<String, dynamic>))
          .toList();
      final folders = (decoded['folders'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          <String>[];
      return BackupData(links: links, folders: folders);
    } catch (_) {
      return null;
    }
  }
}
