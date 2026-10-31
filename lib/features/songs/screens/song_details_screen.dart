import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/song_providers.dart';
import '../widgets/song_action_helpers.dart';
import 'arrangement_editor_screen.dart';
import '../../../core/models/arrangement.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';

class SongDetailsScreen extends ConsumerWidget {
  const SongDetailsScreen({super.key, required this.songId});

  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSongs = ref.watch(groupSongsProvider);
    if (asyncSongs.isLoading) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (asyncSongs.hasError) {
      return Scaffold(
          appBar: AppBar(),
          body:
              Center(child: Text('Could not load songs: ${asyncSongs.error}')));
    }
    final song = ref.watch(songByIdProvider(songId));
    final canEdit = ref.watch(canManageSongsProvider);
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
          if (canEdit)
            IconButton(
                tooltip: 'Delete Song',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final group = ref.read(selectedGroupIdProvider)!;
                  if (!await confirmSongAction(context, 'Delete song?',
                      'Songs used in published or draft setlists cannot be deleted.')) {
                    return;
                  }
                  if (!context.mounted) return;
                  await performSongAction(context, () async {
                    await ref
                        .read(songRepositoryProvider)
                        .deleteSong(group, song.id);
                    if (context.mounted) context.go(RoutePaths.songs);
                  }, 'Song deleted.');
                }),
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
                        Expanded(
                            child: Text(a.name,
                                style: theme.textTheme.titleSmall)),
                        _Pill(label: a.performanceKey),
                        if (canEdit)
                          PopupMenuButton<String>(
                              tooltip: 'Manage ${a.name}',
                              itemBuilder: (_) => [
                                    for (final action in [
                                      'Edit',
                                      'Duplicate',
                                      'Delete'
                                    ])
                                      PopupMenuItem(
                                          value: action, child: Text(action))
                                  ],
                              onSelected: (action) async {
                                final group =
                                    ref.read(selectedGroupIdProvider)!;
                                if (action == 'Edit') {
                                  final edited = await Navigator.of(context)
                                      .push<Arrangement>(MaterialPageRoute(
                                          fullscreenDialog: true,
                                          builder: (_) =>
                                              ArrangementEditorScreen(
                                                  arrangement: a)));
                                  if (edited == null || !context.mounted) {
                                    return;
                                  }
                                  await performSongAction(
                                      context,
                                      () => ref
                                          .read(songRepositoryProvider)
                                          .updateArrangement(
                                              group, song.id, edited),
                                      'Arrangement saved.');
                                } else {
                                  if (action == 'Delete' &&
                                      !await confirmSongAction(
                                          context,
                                          'Delete arrangement?',
                                          'Referenced arrangements cannot be deleted.')) {
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  await performSongAction(context, () async {
                                    final repo =
                                        ref.read(songRepositoryProvider);
                                    if (action == 'Delete') {
                                      await repo.deleteArrangement(
                                          group, song.id, a.id);
                                    } else {
                                      await repo.duplicateArrangement(
                                          group, song.id, a.id);
                                    }
                                  },
                                      action == 'Delete'
                                          ? 'Arrangement deleted.'
                                          : 'Arrangement duplicated.');
                                }
                              }),
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
        ],
      ),
    );
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
