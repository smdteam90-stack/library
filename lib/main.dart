import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/app_strings.dart';
import 'models/saved_link.dart';
import 'screens/save_link_screen.dart';
import 'screens/settings_screen.dart';
import 'services/backup_service.dart';
import 'services/link_meta_service.dart';
import 'services/settings_service.dart';
import 'services/share_intent_service.dart';
import 'services/storage_service.dart';
import 'services/text_export_service.dart';
import 'widgets/link_card.dart';

void main() => runApp(const ContentLibraryApp());

/// Root widget. Owns the app-wide settings (theme, language, text scale) so
/// changing them in the Settings screen updates the whole app immediately.
class ContentLibraryApp extends StatefulWidget {
  const ContentLibraryApp({super.key});

  @override
  State<ContentLibraryApp> createState() => _ContentLibraryAppState();
}

class _ContentLibraryAppState extends State<ContentLibraryApp> {
  final _settingsService = SettingsService();
  AppSettings _settings = AppSettings.defaults;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _settingsLoaded = true;
    });
  }

  void _updateSettings(AppSettings settings) {
    setState(() => _settings = settings);
    _settingsService.save(settings);
  }

  ThemeMode get _themeMode => switch (_settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(_settings.languageCode);
    return MaterialApp(
      title: s.t('appTitle'),
      debugShowCheckedModeBanner: false,
      locale: Locale(_settings.languageCode),
      supportedLocales: const [
        Locale('fa'),
        Locale('en'),
        Locale('ar'),
        Locale('es'),
        Locale('fr'),
        Locale('tr'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6750a4)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff6750a4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_settings.textScale),
        ),
        child: child!,
      ),
      home: _settingsLoaded
          ? LibraryHome(settings: _settings, onSettingsChanged: _updateSettings)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  final _search = TextEditingController();
  final _storage = StorageService();
  final _shareService = ShareIntentService();

  List<SavedLink> _links = [];
  List<String> _folders = [];
  String _activeFolder = ''; // '' means "all folders"
  bool _loading = true;

  AppStrings get _s => AppStrings(widget.settings.languageCode);

  @override
  void initState() {
    super.initState();
    _loadFromDisk();
    _shareService.start(_onSharedUrl);
  }

  @override
  void dispose() {
    _search.dispose();
    _shareService.dispose();
    super.dispose();
  }

  Future<void> _loadFromDisk() async {
    final links = await _storage.loadLinks();
    final storedFolders = await _storage.loadFolders();
    final folderNames = <String>{...storedFolders, ...links.expand((e) => e.folders)}.toList()..sort();
    if (!mounted) return;
    setState(() {
      _links = links;
      _folders = folderNames;
      _loading = false;
    });
  }

  Future<void> _persistLinks() => _storage.saveLinks(_links);
  Future<void> _persistFolders() => _storage.saveFolders(_folders);

  List<SavedLink> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _links.where((item) {
      final inFolder = _activeFolder.isEmpty || item.folders.contains(_activeFolder);
      final text =
          '${item.title} ${item.url} ${item.description} ${item.channel} ${item.source}'
              .toLowerCase();
      return inFolder && (query.isEmpty || text.contains(query));
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // Called whenever a link arrives via the Android share sheet, from any
  // app (Instagram, YouTube, TikTok, Telegram, a browser, ...), whether the
  // app was already open or was launched fresh by the share action.
  Future<void> _onSharedUrl(String sharedText) async {
    final url = _extractUrl(sharedText);
    if (url == null) return;
    if (!mounted) return;
    final result = await Navigator.push<SavedLink>(
      context,
      MaterialPageRoute(
        builder: (_) => SaveLinkScreen(
          languageCode: widget.settings.languageCode,
          sharedUrl: url,
          existingFolders: _folders,
          existingLinks: _links,
        ),
      ),
    );
    if (result == null) return;
    for (final f in result.folders) {
      _addNewFolderIfNeeded(f);
    }
    _addOrRejectDuplicate(result);
  }

  Future<void> _addLinkManually() async {
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(_s.t('addLink')),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: 'https://...'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(_s.t('cancel'))),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                final parsed = Uri.tryParse(value);
                if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) return;
                Navigator.pop(context, value);
              },
              child: Text(_s.t('continueLabel')),
            ),
          ],
        );
      },
    );
    if (url == null) return;
    await _onSharedUrl(url);
  }

  Future<void> _addFolderManually() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_s.t('newFolderTitle')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: _s.t('folderNameLabel'),
            hintText: _s.t('folderNameHint'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(_s.t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(_s.t('create')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    _addNewFolderIfNeeded(name);
  }

  void _addNewFolderIfNeeded(String name) {
    if (name.isEmpty || _folders.contains(name)) return;
    setState(() => _folders = [..._folders, name]..sort());
    _persistFolders();
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.add_link),
              title: Text(_s.t('addLink')),
              onTap: () {
                Navigator.pop(context);
                _addLinkManually();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(_s.t('addFolder')),
              onTap: () {
                Navigator.pop(context);
                _addFolderManually();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addOrRejectDuplicate(SavedLink result) {
    final normalized = _normalizeUrl(result.url);
    final index = _links.indexWhere((item) => _normalizeUrl(item.url) == normalized);
    if (index != -1) {
      // Same link saved again: instead of rejecting it, add it to any new
      // folders chosen this time, so one link can live in several folders.
      final existing = _links[index];
      final merged = <String>{...existing.folders, ...result.folders}.toList();
      final grew = merged.length > existing.folders.length;
      if (grew) {
        setState(() => _links[index] = existing.copyWith(folders: merged));
        _persistLinks();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.t(grew ? 'addedToFoldersMsg' : 'duplicateLinkMsg'))),
      );
      return;
    }
    setState(() => _links = [..._links, result]);
    _persistLinks();
  }

  Future<void> _open(SavedLink item) async {
    final uri = Uri.tryParse(item.url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.t('openFailedMsg'))),
      );
    }
  }

  void _shareLink(SavedLink item) {
    Share.share(item.url);
  }

  void _toggleWatched(SavedLink item) {
    final updated = item.copyWith(watched: !item.watched);
    setState(() {
      final index = _links.indexWhere((x) => x.id == item.id);
      if (index != -1) _links[index] = updated;
    });
    _persistLinks();
  }

  Future<void> _editLink(SavedLink item) async {
    final result = await Navigator.push<SavedLink>(
      context,
      MaterialPageRoute(
        builder: (_) => SaveLinkScreen(
          languageCode: widget.settings.languageCode,
          sharedUrl: item.url,
          existingFolders: _folders,
          existingLinks: _links,
          existing: item,
        ),
      ),
    );
    if (result == null) return;
    for (final f in result.folders) {
      _addNewFolderIfNeeded(f);
    }
    setState(() {
      final index = _links.indexWhere((x) => x.id == item.id);
      if (index != -1) _links[index] = result;
    });
    _persistLinks();
  }

  Future<void> _moveLink(SavedLink item) async {
    final selected = item.folders.toSet();
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_s.t('chooseFoldersTitle')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: _folders
                  .map((f) => CheckboxListTile(
                        title: Text(f),
                        value: selected.contains(f),
                        onChanged: (on) => setLocal(() {
                          if (on == true) {
                            selected.add(f);
                          } else {
                            selected.remove(f);
                          }
                        }),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(_s.t('cancel'))),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(context, selected),
              child: Text(_s.t('save')),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final updated = item.copyWith(folders: chosen.toList());
    setState(() {
      final index = _links.indexWhere((x) => x.id == item.id);
      if (index != -1) _links[index] = updated;
    });
    _persistLinks();
  }

  Future<void> _confirmDelete(SavedLink item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_s.t('deleteConfirmTitle')),
        content: Text(_s.t('deleteConfirmBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_s.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_s.t('deleteLabel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final cached = item.thumbnailFile;
    if (cached != null && cached.isNotEmpty) {
      try {
        await File(cached).delete();
      } catch (_) {}
    }
    setState(() {
      _links.removeWhere((x) => x.id == item.id);
      final folderStillHasLinks = _links.any((x) => x.folders.contains(_activeFolder));
      final folderStillExists = _folders.contains(_activeFolder);
      if (_activeFolder.isNotEmpty && !folderStillHasLinks && !folderStillExists) {
        _activeFolder = '';
      }
    });
    _persistLinks();
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_s.t(key))));
  }

  Future<void> _backupSave() async {
    try {
      final saved = await BackupService.saveToDevice(_links, _folders);
      if (saved) _snack('backupSavedMsg');
    } catch (_) {
      _snack('backupFailedMsg');
    }
  }

  Future<void> _backupShare() async {
    try {
      await BackupService.share(_links, _folders);
    } catch (_) {
      _snack('backupFailedMsg');
    }
  }

  /// Sends a readable, folder-grouped text listing of every saved link
  /// (title + URL, marked if watched) through the normal share sheet. This
  /// is for reading or forwarding the list -- it is not the JSON backup and
  /// cannot be used to restore data into the app.
  Future<void> _shareAsText() async {
    try {
      final text = TextExportService.build(links: _links, folders: _folders, s: _s);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/reelbox-list-$stamp.txt');
      await file.writeAsString(text);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'text/plain')], text: text),
      );
    } catch (_) {
      _snack('backupFailedMsg');
    }
  }

  Future<void> _restore() async {
    try {
      final text = await BackupService.pickBackupText();
      if (text == null) return;
      final data = BackupService.parse(text);
      if (data == null) {
        _snack('restoreInvalidMsg');
        return;
      }
      if (!mounted) return;
      final mode = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_s.t('restoreTitle')),
          content: Text(
            _s
                .t('restoreBody')
                .replaceAll('{links}', '${data.links.length}')
                .replaceAll('{folders}', '${data.folders.length}'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_s.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'replace'),
              child: Text(_s.t('replaceLabel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'merge'),
              child: Text(_s.t('mergeLabel')),
            ),
          ],
        ),
      );
      if (mode == null) return;
      final backupFolders = <String>{...data.folders, ...data.links.expand((l) => l.folders)};
      setState(() {
        if (mode == 'replace') {
          _links = [...data.links];
          _folders = backupFolders.toList()..sort();
        } else {
          final merged = [..._links];
          for (final incoming in data.links) {
            final key = _normalizeUrl(incoming.url);
            final i = merged.indexWhere((x) => _normalizeUrl(x.url) == key);
            if (i == -1) {
              merged.add(incoming);
            } else {
              final union = <String>{...merged[i].folders, ...incoming.folders}.toList();
              merged[i] = merged[i].copyWith(folders: union);
            }
          }
          _links = merged;
          _folders = <String>{..._folders, ...backupFolders}.toList()..sort();
        }
        _activeFolder = '';
      });
      _persistLinks();
      _persistFolders();
      _snack('restoredMsg');
      _fetchMissingThumbnails();
    } catch (_) {
      _snack('restoreInvalidMsg');
    }
  }

  bool _hasThumb(SavedLink l) {
    final f = l.thumbnailFile;
    return f != null && f.isNotEmpty && File(f).existsSync();
  }

  /// Looks up preview images for saved links that have none on the phone
  /// (older saves, restored backups). Returns how many were found.
  Future<int> _fetchMissingThumbnails() async {
    var found = 0;
    final targets = _links.where((l) => !_hasThumb(l)).take(60).toList();
    for (final l in targets) {
      final meta = await LinkMetaService.fetchMeta(l.url);
      if (!mounted) return found;
      if (meta == null) continue;
      final hasImage =
          (meta.imageFile?.isNotEmpty ?? false) || (meta.imageUrl?.isNotEmpty ?? false);
      if (!hasImage) continue;
      final i = _links.indexWhere((x) => x.id == l.id);
      if (i == -1) continue;
      setState(() {
        _links[i] = _links[i].copyWith(
          thumbnailUrl: meta.imageUrl,
          thumbnailFile: meta.imageFile,
        );
      });
      found++;
    }
    if (found > 0) _persistLinks();
    return found;
  }

  Future<void> _fetchThumbsFromSettings() async {
    _snack('fetchThumbsStart');
    final found = await _fetchMissingThumbnails();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_s.t('fetchThumbsDone').replaceAll('{n}', '$found'))),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          onChanged: widget.onSettingsChanged,
          onBackupSave: _backupSave,
          onBackupShare: _backupShare,
          onRestore: _restore,
          onFetchThumbs: _fetchThumbsFromSettings,
          onShareText: _shareAsText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final visible = _visible;
    final showFolders = _activeFolder.isEmpty && _search.text.trim().isEmpty;
    return PopScope(
      canPop: _activeFolder.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _activeFolder = '';
            _search.clear();
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _activeFolder.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() {
                    _activeFolder = '';
                    _search.clear();
                  }),
                ),
          title: Text(_activeFolder.isEmpty ? _s.t('appTitle') : _activeFolder),
          actions: [
            IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddMenu,
          icon: const Icon(Icons.add),
          label: Text(_s.t('addLink')),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: _s.t('searchHint'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            Expanded(
              child: showFolders
                  ? _buildFolderList()
                  : visible.isEmpty
                      ? _EmptyState(s: _s)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                          itemCount: visible.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: LinkCard(
                              item: visible[i],
                              s: _s,
                              onOpen: () => _open(visible[i]),
                              onWatched: () => _toggleWatched(visible[i]),
                              onDelete: () => _confirmDelete(visible[i]),
                              onEdit: () => _editLink(visible[i]),
                              onMove: () => _moveLink(visible[i]),
                              onShare: () => _shareLink(visible[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Default home view: folders first, each with its link count. Tapping a
  /// folder shows the links inside it. Typing in the search box switches to
  /// a flat list of matching links across all folders.
  Widget _buildFolderList() {
    if (_folders.isEmpty) {
      return Center(child: Text(_s.t('noFoldersYet')));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
      itemCount: _folders.length,
      itemBuilder: (_, i) {
        final name = _folders[i];
        final count = _links.where((l) => l.folders.contains(name)).length;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(name),
            subtitle: Text('$count ${_s.t('linksCount')}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _activeFolder = name),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bookmark_border, size: 64),
            const SizedBox(height: 12),
            Text(s.t('emptyTitle')),
            const SizedBox(height: 4),
            Text(s.t('emptySubtitle')),
          ],
        ),
      );
}

/// Pulls a usable URL out of whatever the share sheet handed us -- some
/// apps send the raw URL, others send a sentence with the URL inside it.
String? _extractUrl(String sharedText) {
  final direct = Uri.tryParse(sharedText.trim());
  if (direct != null && direct.hasScheme && direct.hasAuthority) {
    return sharedText.trim();
  }
  final match = RegExp(r'https?://\S+').firstMatch(sharedText);
  return match?.group(0);
}

String _normalizeUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return url.trim().toLowerCase();
  final path = uri.path.endsWith('/') && uri.path.length > 1
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return '${uri.host.toLowerCase()}$path'; // ignore scheme, query, fragment
}
