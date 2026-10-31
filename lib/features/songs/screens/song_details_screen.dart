import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/mock_data/mock_songs.dart';
import '../../../core/models/song.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';

class SongDetailsScreen extends ConsumerWidget {
  const SongDetailsScreen({super.key, required this.songId});

  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = _findSong(songId);
    final role = ref.watch(currentRoleProvider);
    final canEdit = role?.canManageSongs ?? false;
    final theme = Theme.of(context);

    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Song not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(song.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => context.push(RoutePaths.songEditorFor(song.id)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(song.artist, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Pill(label: song.category),
              _Pill(label: 'Default key ${song.defaultKey}'),
              if (song.isFavorite)
                const _Pill(label: 'Favorite', highlight: true),
            ],
          ),
          const SizedBox(height: 20),
          Text('Arrangements', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final a in song.arrangements)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(a.name, style: theme.textTheme.titleSmall),
                        const Spacer(),
                        _Pill(label: a.performanceKey),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${a.bpm} BPM · ${a.timeSignature}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (a.vocalistKeys.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Vocalist keys',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final vk in a.vocalistKeys)
                            _Pill(
                              label: '${vk.vocalistName}: ${vk.key}',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Chart Source', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              song.primaryArrangement.chordProSource,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Chart rendering engine arrives in Phase 2.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  static Song? _findSong(String id) {
    for (final s in mockSongs) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = highlight
        ? AppColors.warning.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest;
    final fg = highlight ? AppColors.warning : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
