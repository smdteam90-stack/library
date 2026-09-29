import 'dart:convert';

class SavedLink {
  SavedLink({
    required this.id,
    required this.url,
    required this.title,
    required this.folders,
    required this.source,
    required this.createdAt,
    this.channel = '',
    this.description = '',
    this.thumbnailUrl,
    this.thumbnailFile,
    this.watched = false,
  });

  final String id;
  final String url;
  final String title;
  final List<String> folders;
  final String source;
  final DateTime createdAt;
  final String channel;
  final String description;
  final String? thumbnailUrl;

  /// Copy of the thumbnail stored on this phone (remote image links often
  /// expire), or null if none was cached.
  final String? thumbnailFile;
  bool watched;

  SavedLink copyWith({
    String? title,
    List<String>? folders,
    String? channel,
    String? description,
    String? thumbnailUrl,
    String? thumbnailFile,
    bool? watched,
  }) =>
      SavedLink(
        id: id,
        url: url,
        title: title ?? this.title,
        folders: folders ?? this.folders,
        source: source,
        createdAt: createdAt,
        channel: channel ?? this.channel,
        description: description ?? this.description,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        thumbnailFile: thumbnailFile ?? this.thumbnailFile,
        watched: watched ?? this.watched,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'folders': folders,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'channel': channel,
        'description': description,
        'thumbnailUrl': thumbnailUrl,
        'thumbnailFile': thumbnailFile,
        'watched': watched,
      };

  factory SavedLink.fromJson(Map<String, dynamic> json) => SavedLink(
        id: json['id'] as String,
        url: json['url'] as String,
        title: json['title'] as String,
        // Older saves stored a single 'folder' string; keep them readable.
        folders: (json['folders'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [json['folder'] as String],
        source: json['source'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        channel: json['channel'] as String? ?? '',
        description: json['description'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String?,
        thumbnailFile: json['thumbnailFile'] as String?,
        watched: json['watched'] as bool? ?? false,
      );

  static String encodeList(List<SavedLink> links) =>
      jsonEncode(links.map((e) => e.toJson()).toList());

  static List<SavedLink> decodeList(String raw) {
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((e) => SavedLink.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
