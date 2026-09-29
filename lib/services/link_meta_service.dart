import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// What could be learned about a link without the user typing anything.
class LinkMeta {
  const LinkMeta({
    this.title = '',
    this.author = '',
    this.description = '',
    this.imageUrl,
    this.imageFile,
  });

  final String title;
  final String author;
  final String description;
  final String? imageUrl;
  final String? imageFile;

  LinkMeta withImage(String? url, String? file) => LinkMeta(
        title: title,
        author: author,
        description: description,
        imageUrl: url,
        imageFile: file,
      );
}

/// Figures out the source app and, where possible, a channel/handle name
/// directly from the shared URL, without any network request. Also offers
/// a best-effort thumbnail lookup via the page's Open Graph metadata.
class LinkMetaService {
  static String sourceFor(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (_endsWithHost(host, 'instagram.com')) return 'Instagram';
    if (_endsWithHost(host, 'youtube.com') || _endsWithHost(host, 'youtu.be')) {
      return 'YouTube';
    }
    if (_endsWithHost(host, 'tiktok.com')) return 'TikTok';
    if (_endsWithHost(host, 't.me') || _endsWithHost(host, 'telegram.me')) {
      return 'Telegram';
    }
    return 'Web';
  }

  /// Best-effort guess at a channel/handle from the URL path itself.
  /// Returns '' when nothing reliable can be extracted -- the field stays
  /// optional and the user can fill it in by hand.
  static String guessChannel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';

    final source = sourceFor(url);
    switch (source) {
      case 'Instagram':
        const reserved = {'reel', 'reels', 'p', 'stories', 'tv', 'explore'};
        if (!reserved.contains(segments.first.toLowerCase())) {
          return '@' + segments.first;
        }
        return '';
      case 'TikTok':
        if (segments.first.startsWith('@')) return segments.first;
        return '';
      case 'Telegram':
        return '@' + segments.first;
      default:
        return '';
    }
  }

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// Best-effort lookup of a title, author/channel, description and preview
  /// image for [url]. YouTube and TikTok publish an open "oEmbed" endpoint
  /// that works without login; other sites (Instagram, blogs, ...) are read
  /// from their Open Graph tags, which Instagram sometimes withholds. The
  /// preview image is copied onto the phone so it does not disappear when
  /// the remote link expires. Returns null when nothing could be found.
  static Future<LinkMeta?> fetchMeta(String url) async {
    try {
      final source = sourceFor(url);
      LinkMeta? meta;
      if (source == 'YouTube') {
        meta = await _oembed(
            'https://www.youtube.com/oembed?format=json&url=${Uri.encodeQueryComponent(url)}');
      } else if (source == 'TikTok') {
        meta = await _oembed(
            'https://www.tiktok.com/oembed?url=${Uri.encodeQueryComponent(url)}');
      }
      meta ??= await _openGraph(url);
      if (source == 'YouTube' && (meta?.imageUrl == null || meta!.imageUrl!.isEmpty)) {
        final id = _youtubeId(url);
        if (id != null) {
          meta = (meta ?? const LinkMeta()).withImage('https://i.ytimg.com/vi/$id/hqdefault.jpg', null);
        }
      }
      if (meta == null) return null;
      final imageUrl = meta.imageUrl;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        final file = await _cacheImage(imageUrl, url);
        meta = meta.withImage(imageUrl, file);
      }
      final empty = meta.title.isEmpty &&
          meta.author.isEmpty &&
          meta.description.isEmpty &&
          (meta.imageUrl == null || meta.imageUrl!.isEmpty);
      return empty ? null : meta;
    } catch (_) {
      return null;
    }
  }

  static Future<LinkMeta?> _oembed(String endpoint) async {
    try {
      final response = await http
          .get(Uri.parse(endpoint), headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return LinkMeta(
        title: _shorten((json['title'] as String?) ?? '', 90),
        author: (json['author_name'] as String?) ?? '',
        imageUrl: json['thumbnail_url'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<LinkMeta?> _openGraph(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': _ua, 'Accept-Language': 'en-US,en;q=0.8'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final tags = _metaTags(body);
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = tags[k];
          if (v != null && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final title = pick(['og:title', 'twitter:title']) ?? _titleTag(body) ?? '';
      final description = pick(['og:description', 'twitter:description', 'description']) ?? '';
      var image = pick(['og:image', 'og:image:url', 'twitter:image']);
      if (image != null) image = Uri.parse(url).resolve(image).toString();
      return LinkMeta(
        title: _shorten(title, 90),
        description: _shorten(description, 160),
        imageUrl: image,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _metaTags(String html) {
    final out = <String, String>{};
    final tagRe = RegExp(r'<meta\s[^>]*>', caseSensitive: false);
    final attrRe = RegExp("([a-zA-Z:\\-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')");
    for (final m in tagRe.allMatches(html)) {
      final attrs = <String, String>{};
      for (final a in attrRe.allMatches(m.group(0)!)) {
        attrs[a.group(1)!.toLowerCase()] = a.group(2) ?? a.group(3) ?? '';
      }
      final key = (attrs['property'] ?? attrs['name'])?.toLowerCase();
      final content = attrs['content'];
      if (key != null && content != null && !out.containsKey(key)) {
        out[key] = _unescape(content);
      }
    }
    return out;
  }

  static String? _titleTag(String html) {
    final m = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html);
    final t = m?.group(1);
    return t == null ? null : _unescape(t).trim();
  }

  /// Decodes the HTML entities found in meta tags. Image links in
  /// particular contain "&amp;" and break if left as-is.
  static String _unescape(String s) {
    var out = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    out = out.replaceAllMapped(
        RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
    return out
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  static String _shorten(String s, int max) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= max) return t;
    final cut = t.substring(0, max);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > max * 0.6 ? cut.substring(0, lastSpace) : cut}…';
  }

  static String? _youtubeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host.toLowerCase().endsWith('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    final seg = uri.pathSegments;
    final i = seg.indexWhere((x) => x == 'shorts' || x == 'embed' || x == 'live' || x == 'v');
    if (i != -1 && i + 1 < seg.length) return seg[i + 1];
    return null;
  }

  /// Downloads the preview image into the app's own storage so it keeps
  /// showing after the remote link expires. Returns the file path, or null.
  static Future<String?> _cacheImage(String imageUrl, String pageUrl) async {
    try {
      final response = await http
          .get(Uri.parse(imageUrl), headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final type = response.headers['content-type'] ?? 'image/';
      final size = response.bodyBytes.length;
      if (!type.startsWith('image/') || size < 500 || size > 3 * 1024 * 1024) return null;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/thumbs');
      if (!await dir.exists()) await dir.create(recursive: true);
      final name =
          'thumb_${pageUrl.hashCode.toUnsigned(32).toRadixString(16)}_${DateTime.now().microsecondsSinceEpoch}.img';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(response.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static bool _endsWithHost(String host, String suffix) =>
      host == suffix || host.endsWith('.' + suffix);
}
