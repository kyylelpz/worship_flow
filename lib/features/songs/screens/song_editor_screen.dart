import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/song.dart';
import '../../../core/models/arrangement.dart';
import '../../../core/router/route_paths.dart';
import '../../auth/providers/auth_providers.dart';
import '../../groups/providers/group_providers.dart';
import '../data/song_validation.dart';
import '../providers/song_providers.dart';
import '../widgets/song_action_helpers.dart';
import 'arrangement_editor_screen.dart';

class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen({super.key, required this.songId});
  const SongEditorScreen.create({super.key}) : songId = '';
  final String songId;
  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends ConsumerState<SongEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _artist = TextEditingController(),
      _category = TextEditingController(),
      _key = TextEditingController(text: 'G');
  late final String? _groupId = ref.read(selectedGroupIdProvider);
  final List<Arrangement> _draftArrangements = [];
  bool _favorite = false, _loaded = false, _saving = false;
  String? _error;
  @override
  void didUpdateWidget(SongEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _loaded = false;
      _error = null;
      _draftArrangements.clear();
      _title.clear();
      _artist.clear();
      _category.clear();
      _key.text = 'G';
      _favorite = false;
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _artist, _category, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(Song? existing) async {
    if (!_form.currentState!.validate() || _saving || _groupId == null) return;
    final editedSongId = widget.songId;
    setState(() {
      _saving = true;
      _error = null;
    });
    final song = Song(
        id: existing?.id ?? '',
        title: _title.text,
        artist: _artist.text,
        category: _category.text,
        defaultKey: _key.text,
        isFavorite: _favorite,
        arrangements: existing?.arrangements ?? _draftArrangements);
    try {
      final repo = ref.read(songRepositoryProvider);
      final String id;
      if (existing == null) {
        id = await repo.createSong(_groupId, song);
      } else {
        await repo.updateSong(_groupId, song);
        id = existing.id;
      }
      if (!mounted ||
          widget.songId != editedSongId ||
          ref.read(selectedGroupIdProvider) != _groupId) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Song saved.')));
      context.go(RoutePaths.songDetailsFor(id));
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editArrangement(Song? song, Arrangement? arrangement) async {
    final value = await Navigator.of(context).push<Arrangement>(
        MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ArrangementEditorScreen(arrangement: arrangement)));
    if (value == null || !mounted) return;
    if (song == null) {
      setState(() {
        final index = _draftArrangements.indexWhere((a) => a.id == value.id);
        if (index < 0) {
          _draftArrangements.add(value);
        } else {
          _draftArrangements[index] = value;
        }
      });
    } else {
      await performSongAction(context, () async {
        final repo = ref.read(songRepositoryProvider);
        if (arrangement == null) {
          await repo.createArrangement(_groupId!, song.id, value);
        } else {
          await repo.updateArrangement(_groupId!, song.id, value);
        }
      }, 'Arrangement saved.');
    }
  }

  Future<void> _arrangementAction(
      Song? song, Arrangement arrangement, String action) async {
    if (action == 'edit') {
      await _editArrangement(song, arrangement);
      return;
    }
    if (action == 'delete') {
      final ok = await confirmSongAction(context, 'Delete arrangement?',
          'Referenced arrangements cannot be deleted. This action cannot be undone.');
      if (!ok || !mounted) return;
    }
    if (song == null) {
      setState(() {
        if (action == 'delete') {
          _draftArrangements.removeWhere((a) => a.id == arrangement.id);
        } else {
          _draftArrangements.add(Arrangement(
              id: const Uuid().v4(),
              name: '${arrangement.name} (Copy)',
              performanceKey: arrangement.performanceKey,
              bpm: arrangement.bpm,
              timeSignature: arrangement.timeSignature,
              chordProSource: arrangement.chordProSource,
              vocalistKeys: arrangement.vocalistKeys));
        }
      });
      return;
    }
    await performSongAction(context, () async {
      final repo = ref.read(songRepositoryProvider);
      if (action == 'delete') {
        await repo.deleteArrangement(_groupId!, song.id, arrangement.id);
      } else {
        await repo.duplicateArrangement(_groupId!, song.id, arrangement.id);
      }
    }, action == 'delete' ? 'Arrangement deleted.' : 'Arrangement duplicated.');
  }

  @override
  Widget build(BuildContext context) {
    final currentGroup = ref.watch(selectedGroupIdProvider);
    final loading = ref.watch(groupSongsProvider).isLoading ||
        ref.watch(allGroupsProvider).isLoading;
    final canEdit =
        ref.watch(canManageSongsProvider) && currentGroup == _groupId;
    final song = widget.songId.isEmpty
        ? null
        : ref.watch(songByIdProvider(widget.songId));
    if (loading) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (!canEdit || _groupId == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(
              child: Text(
                  'Song management permission is required. Reopen the editor after switching groups.')));
    }
    if (widget.songId.isNotEmpty && song == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Song not found in this group.')));
    }
    if (!_loaded) {
      if (song != null) {
        _title.text = song.title;
        _artist.text = song.artist;
        _category.text = song.category;
        _key.text = song.defaultKey;
        _favorite = song.isFavorite;
      }
      _loaded = true;
    }
    final arrangements = song?.arrangements ?? _draftArrangements;
    return Scaffold(
      appBar: AppBar(
          title: Text(song == null ? 'New Song' : 'Edit Song'),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => _save(song),
                child: Text(_saving ? 'Saving…' : 'Save Song')),
          ]),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: SongValidation.requiredText),
            const SizedBox(height: 16),
            TextFormField(
                controller: _artist,
                decoration: const InputDecoration(labelText: 'Artist'),
                validator: SongValidation.requiredText),
            const SizedBox(height: 16),
            TextFormField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                validator: SongValidation.requiredText),
            const SizedBox(height: 16),
            TextFormField(
                controller: _key,
                decoration: const InputDecoration(labelText: 'Default key'),
                validator: SongValidation.key),
            const SizedBox(height: 16),
            SwitchListTile(
                title: const Text('Favorite'),
                value: _favorite,
                onChanged: (v) => setState(() => _favorite = v)),
            const SizedBox(height: 16),
            Text('Arrangements', style: Theme.of(context).textTheme.titleLarge),
            if (song != null)
              const Text(
                  'Arrangement changes are saved immediately. Save Song applies song metadata.'),
            for (final arrangement in arrangements)
              Card(
                  child: ListTile(
                      title: Text(arrangement.name),
                      subtitle: Text(
                          '${arrangement.performanceKey} · ${arrangement.bpm} BPM · ${arrangement.timeSignature}'),
                      onTap: () => _editArrangement(song, arrangement),
                      trailing: PopupMenuButton<String>(
                          tooltip: 'Manage ${arrangement.name}',
                          onSelected: (action) =>
                              _arrangementAction(song, arrangement, action),
                          itemBuilder: (_) => [
                                for (final action in [
                                  'edit',
                                  'duplicate',
                                  'delete'
                                ])
                                  PopupMenuItem(
                                      value: action,
                                      child: Text(
                                          '${action[0].toUpperCase()}${action.substring(1)}'))
                              ]))),
            TextButton.icon(
                onPressed: () => _editArrangement(song, null),
                icon: const Icon(Icons.add),
                label: const Text('Add Arrangement')),
          ])),
    );
  }
}
