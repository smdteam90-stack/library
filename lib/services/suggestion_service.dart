import '../models/saved_link.dart';

/// Suggests which of the user's existing folders a new link probably
/// belongs in. This is plain keyword/habit matching, not AI, so it works
/// offline and gets better as more links are saved.
class SuggestionService {
  static List<String> suggestFolders({
    required List<String> folders,
    required List<SavedLink> links,
    required String title,
    required String channel,
    required String description,
    int max = 3,
  }) {
    final text = '$title $description $channel'.toLowerCase();
    final words = _words(text);
    final channelKey = channel.trim().toLowerCase();
    final scores = <String, double>{};

    for (final folder in folders) {
      var score = 0.0;
      final name = folder.trim().toLowerCase();
      if (name.length >= 2 && text.contains(name)) score += 4;
      for (final w in _words(name)) {
        if (w.length >= 3 && text.contains(w)) score += 2;
      }

      final inFolder = links.where((l) => l.folders.contains(folder)).toList();

      // Same channel/page saved into this folder before: strongest habit.
      if (channelKey.isNotEmpty &&
          inFolder.any((l) => l.channel.trim().toLowerCase() == channelKey)) {
        score += 5;
      }

      // Words shared with titles/descriptions already in this folder.
      final folderWords = <String>{};
      for (final l in inFolder) {
        folderWords.addAll(_words('${l.title} ${l.description}'.toLowerCase()));
      }
      var overlap = 0;
      for (final w in words) {
        if (w.length >= 4 && folderWords.contains(w)) overlap++;
      }
      score += overlap > 4 ? 4 : overlap.toDouble();

      if (score >= 2) scores[folder] = score;
    }

    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(max).map((e) => e.key).toList();
  }

  static Set<String> _words(String s) => s
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toSet();
}
