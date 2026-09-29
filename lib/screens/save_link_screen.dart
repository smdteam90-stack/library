import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/saved_link.dart';
import '../services/link_meta_service.dart';
import '../services/suggestion_service.dart';

/// Shown right after a link arrives via share (or via the manual "+" menu),
/// and reused (with [existing] set) to edit a link that was already saved.
class SaveLinkScreen extends StatefulWidget {
  const SaveLinkScreen({
    super.key,
    required this.languageCode,
    required this.sharedUrl,
    required this.existingFolders,
    required this.existingLinks,
    this.existing,
  });

  final String languageCode;
  final String sharedUrl;
  final List<String> existingFolders;
  final List<SavedLink> existingLinks;
  final SavedLink? existing;

  @override
  State<SaveLinkScreen> createState() => _SaveLinkScreenState();
}

class _SaveLinkScreenState extends State<SaveLinkScreen> {
  late final TextEditingController _title;
  late final TextEditingController _channel;
  late final TextEditingController _description;
  late final TextEditingController _newFolder;
  final _folderSearch = TextEditingController();
  final Set<String> _selectedFolders = {};
  bool _creatingNewFolder = false;
  String? _thumbnailUrl;
  String? _thumbnailFile;
  List<String> _suggested = [];
  bool _fetchingThumbnail = false;

  AppStrings get _s => AppStrings(widget.languageCode);
  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final source = LinkMetaService.sourceFor(widget.sharedUrl);
    _title = TextEditingController(text: existing?.title ?? source);
    _channel = TextEditingController(
      text: existing?.channel ?? LinkMetaService.guessChannel(widget.sharedUrl),
    );
    _description = TextEditingController(text: existing?.description ?? '');
    _newFolder = TextEditingController();
    _thumbnailUrl = existing?.thumbnailUrl;
    _thumbnailFile = existing?.thumbnailFile;
    if (existing != null) _selectedFolders.addAll(existing.folders);
    if (widget.existingFolders.isEmpty && !_isEditing) _creatingNewFolder = true;
    _refreshSuggestions();
    if (!_isEditing) _fetchMeta();
  }

  Future<void> _fetchMeta() async {
    setState(() => _fetchingThumbnail = true);
    final meta = await LinkMetaService.fetchMeta(widget.sharedUrl);
    if (!mounted) return;
    setState(() {
      _fetchingThumbnail = false;
      if (meta == null) return;
      _thumbnailUrl = meta.imageUrl;
      _thumbnailFile = meta.imageFile;
      // Only fill fields the user has not typed into yet.
      final source = LinkMetaService.sourceFor(widget.sharedUrl);
      final currentTitle = _title.text.trim();
      if (meta.title.isNotEmpty && (currentTitle.isEmpty || currentTitle == source)) {
        _title.text = meta.title;
      }
      if (meta.author.isNotEmpty && _channel.text.trim().isEmpty) {
        _channel.text = meta.author;
      }
      if (meta.description.isNotEmpty && _description.text.trim().isEmpty) {
        _description.text = meta.description;
      }
      _refreshSuggestions();
    });
  }

  void _refreshSuggestions() {
    if (_isEditing) return;
    _suggested = SuggestionService.suggestFolders(
      folders: widget.existingFolders,
      links: widget.existingLinks,
      title: _title.text,
      channel: _channel.text,
      description: _description.text,
    );
  }

  bool get _hasPreview =>
      (_thumbnailFile?.isNotEmpty ?? false) || (_thumbnailUrl?.isNotEmpty ?? false);

  Widget _previewImage() {
    final file = _thumbnailFile;
    if (file != null && file.isNotEmpty && File(file).existsSync()) {
      return Image.file(
        File(file),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return Image.network(
      _thumbnailUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _channel.dispose();
    _description.dispose();
    _newFolder.dispose();
    _folderSearch.dispose();
    super.dispose();
  }

  void _save() {
    final folders = <String>[..._selectedFolders];
    final newName = _creatingNewFolder ? _newFolder.text.trim() : '';
    if (newName.isNotEmpty && !folders.contains(newName)) folders.add(newName);
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_s.t('folderRequiredError'))),
      );
      return;
    }
    final source = LinkMetaService.sourceFor(widget.sharedUrl);
    final existing = widget.existing;
    final link = SavedLink(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      url: widget.sharedUrl,
      title: _title.text.trim().isEmpty ? source : _title.text.trim(),
      folders: folders,
      source: existing?.source ?? source,
      channel: _channel.text.trim(),
      description: _description.text.trim(),
      thumbnailUrl: _thumbnailUrl,
      thumbnailFile: _thumbnailFile,
      createdAt: existing?.createdAt ?? DateTime.now(),
      watched: existing?.watched ?? false,
    );
    Navigator.pop(context, link);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? _s.t('editTitle') : _s.t('saveTitle'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.sharedUrl,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
            ),
            if (_fetchingThumbnail) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (_thumbnailUrl != null && _thumbnailUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _previewImage(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(_s.t('folderRequiredLabel'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(_s.t('folderMultiHint'), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            if (_suggested.isNotEmpty && !_isEditing) ...[
              Text(_s.t('suggestedFolders'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _suggested
                    .map((f) => ActionChip(
                          avatar: const Icon(Icons.auto_awesome, size: 16),
                          label: Text(f),
                          onPressed: () => setState(() => _selectedFolders.add(f)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.existingFolders.length > 5) ...[
              TextField(
                controller: _folderSearch,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: _s.t('folderSearchHint'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...widget.existingFolders
                    .where((f) => f
                        .toLowerCase()
                        .contains(_folderSearch.text.trim().toLowerCase()))
                    .map(
                  (f) => FilterChip(
                    label: Text(f),
                    selected: _selectedFolders.contains(f),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selectedFolders.add(f);
                      } else {
                        _selectedFolders.remove(f);
                      }
                    }),
                  ),
                ),
                FilterChip(
                  label: Text(_s.t('newFolderChip')),
                  selected: _creatingNewFolder,
                  onSelected: (on) => setState(() => _creatingNewFolder = on),
                ),
              ],
            ),
            if (_creatingNewFolder) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _newFolder,
                decoration: InputDecoration(
                  labelText: _s.t('folderNameLabel'),
                  hintText: _s.t('folderNameHint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: _s.t('titleLabel'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _channel,
              decoration: InputDecoration(
                labelText: _s.t('channelLabel'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _s.t('descriptionLabel'),
                hintText: _s.t('descriptionHint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(_s.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
