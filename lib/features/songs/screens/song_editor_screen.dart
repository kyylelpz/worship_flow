import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/mock_data/mock_songs.dart';
import '../../../core/models/song.dart';
import '../../../core/theme/app_colors.dart';

class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen({super.key, required this.songId});

  final String songId;

  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends ConsumerState<SongEditorScreen> {
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _keyController = TextEditingController();
  final _chordProController = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final song = _findSong(widget.songId);
    if (song != null) {
      _titleController.text = song.title;
      _artistController.text = song.artist;
      _keyController.text = song.defaultKey;
      _chordProController.text = song.primaryArrangement.chordProSource;
    }
    _loaded = true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _keyController.dispose();
    _chordProController.dispose();
    super.dispose();
  }

  static Song? _findSong(String id) {
    for (final s in mockSongs) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Song save will be wired with Firestore in Phase 2.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Song'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _artistController,
            decoration: const InputDecoration(labelText: 'Artist'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            decoration: const InputDecoration(labelText: 'Default key'),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('ChordPro Source', style: theme.textTheme.titleMedium),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'raw',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _chordProController,
            maxLines: 20,
            minLines: 12,
            style: const TextStyle(
              fontFamily: 'monospace',
              height: 1.5,
            ),
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              hintText: '[G]Sample chord line',
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: AppColors.lightSecondaryText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Preview',
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Visual ChordPro preview arrives in Phase 2. '
                    'Raw text above is the source of truth.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.pop(),
            child: const Text('Back to Song'),
          ),
        ],
      ),
    );
  }
}
