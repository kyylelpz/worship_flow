import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/mock_data/mock_songs.dart';
import '../../../core/models/setlist.dart';
import '../../../core/models/setlist_item.dart';
import '../../../core/models/song.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/setlist_providers.dart';

class SetlistDetailsScreen extends ConsumerWidget {
  const SetlistDetailsScreen({super.key, required this.setlistId});

  final String setlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSetlist = ref.watch(setlistByIdProvider(setlistId));
    final role = ref.watch(currentRoleProvider);
    final canEdit = role?.canManageSetlists ?? false;

    return asyncSetlist.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Could not load setlist:\n$e')),
      ),
      data: (setlist) {
        if (setlist == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Setlist not found.')),
          );
        }
        return _DetailsBody(setlist: setlist, canEdit: canEdit);
      },
    );
  }
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({required this.setlist, required this.canEdit});

  final Setlist setlist;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = setlist.displayItems;
    final songsById = {for (final s in mockSongs) s.id: s};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Setlist'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (value) => _onAction(context, ref, value),
            itemBuilder: (_) => [
              if (canEdit) ...[
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_rounded),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: ListTile(
                    leading: Icon(Icons.copy_rounded),
                    title: Text('Duplicate'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (setlist.status == SetlistStatus.draft ||
                    setlist.hasDraftChanges)
                  const PopupMenuItem(
                    value: 'publish',
                    child: ListTile(
                      leading: Icon(Icons.cloud_upload_rounded),
                      title: Text('Publish'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
              if (canEdit)
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Delete'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (!canEdit)
                const PopupMenuItem(
                  value: 'none',
                  enabled: false,
                  child: ListTile(
                    leading: Icon(Icons.lock_outline_rounded),
                    title: Text('Read-only'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          _Header(setlist: setlist),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Songs', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                '${items.length} ${items.length == 1 ? "song" : "songs"}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const _EmptySongs()
          else
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SongRow(
                  index: i + 1,
                  item: items[i],
                  song: songsById[items[i].songId],
                  onTap: () {
                    final song = songsById[items[i].songId];
                    if (song != null) {
                      context.push(RoutePaths.songDetailsFor(song.id));
                    }
                  },
                ),
              ),
        ],
      ),
      bottomNavigationBar: _BottomBar(setlist: setlist),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final repo = ref.read(setlistRepositoryProvider);
    switch (value) {
      case 'edit':
        unawaited(context.push(RoutePaths.setlistEditorFor(setlist.id)));
        break;
      case 'duplicate':
        final newId = await repo.duplicate(setlist.id);
        if (!context.mounted) return;
        ref.invalidate(setlistByIdProvider(setlist.id));
        unawaited(context.push(RoutePaths.setlistDetailsFor(newId)));
        break;
      case 'publish':
        final ok = await _confirm(context,
            title: 'Publish this setlist?',
            message:
                'This will publish the current draft and notify the team.');
        if (!ok) return;
        await repo.publish(setlist.id);
        if (!context.mounted) return;
        ref.invalidate(setlistByIdProvider(setlist.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Setlist published.')),
        );
        break;
      case 'delete':
        final ok = await _confirm(
          context,
          title: 'Delete setlist?',
          message: 'This cannot be undone.',
          destructive: true,
        );
        if (!ok) return;
        await repo.delete(setlist.id);
        if (!context.mounted) return;
        context.pop();
        break;
      case 'none':
        break;
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(destructive ? 'Delete' : 'Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.setlist});

  final Setlist setlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel =
        DateFormat('EEEE, MMM d · h:mm a').format(setlist.serviceDateTime);
    final isPublished = setlist.status == SetlistStatus.published;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(setlist.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(dateLabel, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Chip(
              label: isPublished ? 'Published' : 'Draft',
              color: isPublished ? AppColors.success : AppColors.warning,
            ),
            if (setlist.hasDraftChanges)
              const _Chip(
                label: 'Unpublished changes',
                color: AppColors.warning,
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.index,
    required this.item,
    required this.song,
    required this.onTap,
  });

  final int index;
  final SetlistItem item;
  final Song? song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrangement =
        song?.arrangements.where((a) => a.id == item.arrangementId).firstOrNull;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: song == null ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$index',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.lightSecondaryText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song?.title ?? 'Unknown song',
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _Meta(label: item.performanceKey),
                        const SizedBox(width: 8),
                        if (arrangement != null) ...[
                          _Meta(label: arrangement.name),
                          const SizedBox(width: 8),
                          _Meta(label: '${arrangement.bpm} BPM'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptySongs extends StatelessWidget {
  const _EmptySongs();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.music_off_rounded,
              size: 40,
              color: AppColors.lightSecondaryText,
            ),
            const SizedBox(height: 8),
            Text('No songs yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add songs in the setlist editor.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.setlist});

  final Setlist setlist;

  @override
  Widget build(BuildContext context) {
    final hasSongs = setlist.displayItems.isNotEmpty;

    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hasSongs
                  ? () => context.push(
                        RoutePaths.setlistRehearsalFor(setlist.id),
                      )
                  : null,
              icon: const Icon(Icons.headphones_rounded, size: 20),
              label: const Text('Rehearse'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: hasSongs
                  ? () => context.push(
                        RoutePaths.setlistLiveFor(setlist.id),
                      )
                  : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Live Mode'),
            ),
          ),
        ],
      ),
    );
  }
}
