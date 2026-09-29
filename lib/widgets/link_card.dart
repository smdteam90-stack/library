import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import '../models/saved_link.dart';

class LinkCard extends StatelessWidget {
  const LinkCard({
    super.key,
    required this.item,
    required this.s,
    required this.onOpen,
    required this.onWatched,
    required this.onDelete,
    required this.onEdit,
    required this.onMove,
    required this.onShare,
  });

  final SavedLink item;
  final AppStrings s;
  final VoidCallback onOpen;
  final VoidCallback onWatched;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onMove;
  final VoidCallback onShare;

  /// Prefers the copy saved on the phone, falls back to the remote link.
  Widget? _thumbnail() {
    final file = item.thumbnailFile;
    if (file != null && file.isNotEmpty && File(file).existsSync()) {
      return Image.file(
        File(file),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    final url = item.thumbnailUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('yyyy/MM/dd').format(item.createdAt);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_thumbnail() != null)
              AspectRatio(aspectRatio: 16 / 9, child: _thumbnail()!),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        child: Text(_sourceIcon(item.source), style: const TextStyle(fontSize: 10)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: item.watched ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (choice) {
                          switch (choice) {
                            case 'watched':
                              onWatched();
                              break;
                            case 'edit':
                              onEdit();
                              break;
                            case 'move':
                              onMove();
                              break;
                            case 'share':
                              onShare();
                              break;
                            case 'delete':
                              onDelete();
                              break;
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'watched',
                            child: Text(item.watched ? s.t('markUnwatched') : s.t('markWatched')),
                          ),
                          PopupMenuItem(value: 'edit', child: Text(s.t('editLabel'))),
                          PopupMenuItem(value: 'move', child: Text(s.t('moveLabel'))),
                          PopupMenuItem(value: 'share', child: Text(s.t('shareLabel'))),
                          PopupMenuItem(value: 'delete', child: Text(s.t('deleteLabel'))),
                        ],
                      ),
                    ],
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Tag(icon: Icons.folder_outlined, label: item.folders.join(' · ')),
                      if (item.channel.isNotEmpty) _Tag(icon: Icons.person_outline, label: item.channel),
                      _Tag(icon: Icons.event_outlined, label: dateLabel),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      );
}

String _sourceIcon(String source) => switch (source) {
      'Instagram' => 'IG',
      'YouTube' => 'YT',
      'TikTok' => 'TT',
      'Telegram' => 'TG',
      _ => 'WEB',
    };
