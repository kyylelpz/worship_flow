import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/mock_data/mock_songs.dart';
import '../../../core/models/arrangement.dart';
import '../../../core/models/setlist_item.dart';
import '../../../core/models/song.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/setlist_providers.dart';

class SetlistEditorScreen extends ConsumerStatefulWidget {
  const SetlistEditorScreen({super.key, required this.setlistId});

  final String setlistId;

  @override
  ConsumerState<SetlistEditorScreen> createState() =>
      _SetlistEditorScreenState();
}

class _SetlistEditorScreenState extends ConsumerState<SetlistEditorScreen> {
  final _nameController = TextEditingController();
  DateTime? _serviceDateTime;
  List<SetlistItem> _items = [];
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final setlist =
        await ref.read(setlistRepositoryProvider).getSetlist(widget.setlistId);
    if (!mounted || setlist == null) return;
    setState(() {
      _nameController.text = setlist.name;
      _serviceDateTime = setlist.serviceDateTime;
      _items = List<SetlistItem>.from(
        setlist.draftItems ?? setlist.publishedItems,
      );
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _saveDraft() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(setlistRepositoryProvider).updateMetadata(
            widget.setlistId,
            name: _nameController.text.trim().isEmpty
                ? 'Untitled Setlist'
                : _nameController.text.trim(),
            serviceDateTime: _serviceDateTime,
          );
      await ref
          .read(setlistRepositoryProvider)
          .saveDraft(widget.setlistId, _items);
      ref.invalidate(setlistByIdProvider(widget.setlistId));
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Future<void> _publish() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publish setlist?'),
        content: const Text(
          'Your current draft will become the published setlist the team '
          'rehearses from.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _saveDraft();
    if (!mounted) return;
    await ref.read(setlistRepositoryProvider).publish(widget.setlistId);
    ref.invalidate(setlistByIdProvider(widget.setlistId));
    if (!mounted) return;
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Setlist published.')),
    );
  }

  Future<void> _pickDateTime() async {
    final current = _serviceDateTime ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      _serviceDateTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _dirty = true;
    });
  }

  Future<void> _addSongs() async {
    final selected = await showModalBottomSheet<List<Song>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _SongPickerSheet(),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() {
      for (final song in selected) {
        final arr = song.primaryArrangement;
        _items.add(SetlistItem(
          songId: song.id,
          arrangementId: arr.id,
          performanceKey: arr.performanceKey,
        ));
      }
      _dirty = true;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
      _dirty = true;
    });
  }

  void _remove(int index) {
    setState(() {
      _items.removeAt(index);
      _dirty = true;
    });
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    final song = _songFor(item.songId);
    if (song == null) return;
    final result = await showModalBottomSheet<SetlistItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemConfigSheet(song: song, item: item),
    );
    if (result != null && mounted) {
      setState(() {
        _items[index] = result;
        _dirty = true;
      });
    }
  }

  Song? _songFor(String id) {
    for (final s in mockSongs) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
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

    return PopScope(
      canPop: !_dirty,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (ok && mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Setlist'),
          actions: [
            TextButton(
              onPressed: _dirty && !_saving ? _saveDraft : null,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Setlist name'),
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDateTime,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Service date & time',
                  suffixIcon: Icon(Icons.calendar_today_rounded),
                ),
                child: Text(
                  _serviceDateTime == null
                      ? 'Not set'
                      : DateFormat('EEE, MMM d · h:mm a')
                          .format(_serviceDateTime!),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Songs', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Text(
                  '(${_items.length})',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addSongs,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              _EmptySongs(onAdd: _addSongs)
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                onReorder: _reorder,
                buildDefaultDragHandles: false,
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  final song = _songFor(item.songId);
                  return Padding(
                    key: ValueKey('item-$i-${item.songId}'),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _EditorSongTile(
                      index: i,
                      item: item,
                      song: song,
                      onTap: () => _editItem(i),
                      onRemove: () => _remove(i),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _publish,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('Publish Setlist'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSongTile extends StatelessWidget {
  const _EditorSongTile({
    required this.index,
    required this.item,
    required this.song,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final SetlistItem item;
  final Song? song;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrangement =
        song?.arrangements.where((a) => a.id == item.arrangementId).firstOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_indicator_rounded),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${song?.title ?? "Unknown"}',
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          item.performanceKey,
                          if (arrangement != null) arrangement.name,
                          if (arrangement != null) '${arrangement.bpm} BPM',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySongs extends StatelessWidget {
  const _EmptySongs({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.playlist_add_rounded,
              size: 40,
              color: AppColors.lightSecondaryText,
            ),
            const SizedBox(height: 8),
            Text('No songs yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add songs to build the setlist.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Songs'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongPickerSheet extends StatefulWidget {
  const _SongPickerSheet();

  @override
  State<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends State<_SongPickerSheet> {
  final _selected = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = mockSongs.where((s) {
      final q = _query.toLowerCase();
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q);
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          children: [
            Row(
              children: [
                Text('Add Songs', style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final picked = mockSongs
                        .where((s) => _selected.contains(s.id))
                        .toList();
                    Navigator.of(ctx).pop(picked);
                  },
                  child: Text('Add (${_selected.length})'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search by title or artist',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final s = filtered[i];
                  final isSel = _selected.contains(s.id);
                  return CheckboxListTile(
                    value: isSel,
                    title: Text(s.title),
                    subtitle: Text(s.artist),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(s.id);
                        } else {
                          _selected.remove(s.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemConfigSheet extends StatefulWidget {
  const _ItemConfigSheet({required this.song, required this.item});

  final Song song;
  final SetlistItem item;

  @override
  State<_ItemConfigSheet> createState() => _ItemConfigSheetState();
}

class _ItemConfigSheetState extends State<_ItemConfigSheet> {
  late String _arrangementId;
  late String _key;

  @override
  void initState() {
    super.initState();
    _arrangementId = widget.item.arrangementId;
    _key = widget.item.performanceKey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrangement = widget.song.arrangements
        .where((a) => a.id == _arrangementId)
        .firstOrNull;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.song.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(widget.song.artist, style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          Text('Arrangement', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final a in widget.song.arrangements)
            RadioListTile<String>(
              value: a.id,
              groupValue: _arrangementId,
              contentPadding: EdgeInsets.zero,
              title: Text(a.name),
              subtitle: Text('${a.bpm} BPM · ${a.timeSignature}'),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _arrangementId = v;
                    _key = a.performanceKey;
                  });
                }
              },
            ),
          const SizedBox(height: 16),
          if (arrangement != null) ...[
            Text('Performance Key', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in _keyOptions(arrangement))
                  ChoiceChip(
                    label: Text(k),
                    selected: _key == k,
                    onSelected: (_) => setState(() => _key = k),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(SetlistItem(
                songId: widget.song.id,
                arrangementId: _arrangementId,
                performanceKey: _key,
              ));
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  List<String> _keyOptions(Arrangement arrangement) {
    // Simple key set — full transposition arrives in Phase 2/3.
    const keys = [
      'C',
      'C#',
      'D',
      'Eb',
      'E',
      'F',
      'F#',
      'G',
      'Ab',
      'A',
      'Bb',
      'B',
    ];
    final presetKeys = arrangement.vocalistKeys.map((v) => v.key).toSet();
    final ordered = <String>{
      arrangement.performanceKey,
      ...presetKeys,
      ...keys
    };
    return ordered.toList();
  }
}
