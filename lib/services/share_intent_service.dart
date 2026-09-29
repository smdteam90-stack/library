import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Listens for links shared into this app from other apps (Instagram,
/// YouTube, Telegram, a browser, etc.) via the Android share sheet.
///
/// Handles both cases:
///  - app was already running in the background
///  - app was launched fresh by tapping "Content Library" in the share sheet
class ShareIntentService {
  StreamSubscription? _mediaStreamSub;

  /// [onUrlShared] fires once per shared item with the raw shared text/URL.
  void start(void Function(String sharedText) onUrlShared) {
    // Item shared while the app is already alive.
    _mediaStreamSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) => _handleSharedItems(files, onUrlShared),
      onError: (_) {},
    );

    // Item that launched the app from a cold start.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedItems(files, onUrlShared);
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _handleSharedItems(
    List<SharedMediaFile> files,
    void Function(String sharedText) onUrlShared,
  ) {
    for (final file in files) {
      final text = file.path.trim();
      if (text.isNotEmpty) onUrlShared(text);
    }
  }

  void dispose() {
    _mediaStreamSub?.cancel();
  }
}
