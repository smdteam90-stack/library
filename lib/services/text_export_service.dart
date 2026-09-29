import '../l10n/app_strings.dart';
import '../models/saved_link.dart';

/// Builds a plain, human-readable text listing of saved links grouped by
/// folder -- meant for sharing to Telegram/email so the person has a
/// readable copy of their list, separate from the JSON backup used to
/// restore data into the app itself.
class TextExportService {
  static String build({
    required List<SavedLink> links,
    required List<String> folders,
    required AppStrings s,
  }) {
    if (links.isEmpty) return s.t('exportEmptyMsg');

    // Folders in the user's own order first, then any folder that only
    // appears on a link (e.g. from an older backup) but isn't in the list.
    final ordered = <String>[
      ...folders,
      ...{for (final l in links) ...l.folders}.where((f) => !folders.contains(f)),
    ];

    final buffer = StringBuffer();
    var first = true;
    for (final folder in ordered) {
      final inFolder = links.where((l) => l.folders.contains(folder)).toList();
      if (inFolder.isEmpty) continue;
      if (!first) buffer.writeln();
      first = false;
      buffer.writeln('\ud83d\udcc1 $folder (${inFolder.length} ${s.t('linksCount')})');
      for (var i = 0; i < inFolder.length; i++) {
        final link = inFolder[i];
        final mark = link.watched ? '\u2705 ' : '';
        final title = link.title.trim().isEmpty ? link.url : link.title.trim();
        buffer.writeln('${i + 1}. $mark$title');
        buffer.writeln('   ${link.url}');
      }
    }
    return buffer.toString().trimRight();
  }
}
