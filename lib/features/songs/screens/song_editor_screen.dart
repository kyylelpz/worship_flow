import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/song.dart';
import '../../../core/models/vocalist_key.dart';
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
      _category = TextEditingController();
  String _categoryChoice = 'Praise';
  final List<_VocalistFields> _vocalists = [];
  late final String? _groupId = ref.read(selectedGroupIdProvider);
  final List<Arrangement> _draftArrangements = [];
  bool _favorite = false, _loaded = false, _saving = false;
  String? _error;
  (String, String, String, String, bool)? _initialMetadata;
  bool _allowExit = false, _leaving = false;
  (String, String, String, String, bool) get _metadata => (
        _title.text,
        _artist.text,
        _categoryChoice == 'Other' ? _category.text : _categoryChoice,
        _vocalists.map((v) => '${v.name.text}=${v.key.text}').join('\n'),
        _favorite
      );
  bool get _hasUnsavedChanges =>
      _loaded &&
      (_metadata != _initialMetadata ||
          (widget.songId.isEmpty && _draftArrangements.isNotEmpty));

  @override
  void initState() {
    super.initState();
    for (final controller in [_title, _artist, _category]) {
      controller.addListener(_metadataChanged);
    }
  }

  void _metadataChanged() {
    if (_loaded && mounted) setState(() {});
  }

  void _addPreset(String name, String key) {
    final fields = _VocalistFields(name, key);
    fields.name.addListener(_metadataChanged);
    fields.key.addListener(_metadataChanged);
    _vocalists.add(fields);
  }

  Future<void> _requestBack() async {
    if (_saving || _leaving) return;
    _leaving = true;
    final discard = !_hasUnsavedChanges ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard changes?'),
                content: const Text('You have unsaved song changes.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep editing')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Discard')),
                ],
              ),
            ) ==
            true;
    if (!mounted) return;
    if (!discard) {
      _leaving = false;
      return;
    }
    // Rebuild PopScope before popping so confirmed Android Back is not blocked.
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(RoutePaths.songs);
      }
    });
  }

  Widget _backButton() => IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: _saving ? null : _requestBack);
  Widget _guardBack(Widget child) => PopScope(
        canPop: (_allowExit || (!_hasUnsavedChanges && !_saving)) &&
            GoRouter.of(context).canPop(),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_requestBack());
        },
        child: child,
      );

  @override
  void didUpdateWidget(SongEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId) {
      _loaded = false;
      _initialMetadata = null;
      _allowExit = false;
      _error = null;
      _draftArrangements.clear();
      _title.clear();
      _artist.clear();
      _category.clear();
      _categoryChoice = 'Praise';
      for (final v in _vocalists) {
        v.dispose();
      }
      _vocalists.clear();
      _favorite = false;
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _artist, _category]) {
      c.dispose();
    }
    for (final v in _vocalists) {
      v.dispose();
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
        category: _categoryChoice == 'Other' ? _category.text : _categoryChoice,
        vocalistKeys: [
          for (final v in _vocalists)
            VocalistKey(vocalistName: v.name.text, key: v.key.text)
        ],
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
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(existing == null
              ? RoutePaths.songs
              : RoutePaths.songDetailsFor(id));
        }
      });
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
              bpm: arrangement.bpm,
              timeSignature: arrangement.timeSignature,
              chordProSource: arrangement.chordProSource,
              referenceLink: arrangement.referenceLink));
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
      return _guardBack(Scaffold(
          appBar: AppBar(leading: _backButton()),
          body: const Center(child: CircularProgressIndicator())));
    }
    if (!canEdit || _groupId == null) {
      return _guardBack(Scaffold(
          appBar: AppBar(leading: _backButton()),
          body: const Center(
              child: Text(
                  'Song management permission is required. Reopen the editor after switching groups.'))));
    }
    if (widget.songId.isNotEmpty && song == null) {
      return _guardBack(Scaffold(
          appBar: AppBar(leading: _backButton()),
          body: const Center(child: Text('Song not found in this group.'))));
    }
    if (!_loaded) {
      if (song != null) {
        _title.text = song.title;
        _artist.text = song.artist;
        _category.text = song.category;
        _categoryChoice =
            const ['Praise', 'Worship', 'Communion'].contains(song.category)
                ? song.category
                : 'Other';
        for (final v in song.vocalistKeys) {
          _addPreset(v.vocalistName, v.key);
        }
        _favorite = song.isFavorite;
      }
      _initialMetadata = _metadata;
      _loaded = true;
    }
    final arrangements = song?.arrangements ?? _draftArrangements;
    return _guardBack(Scaffold(
      appBar: AppBar(
          leading: _backButton(),
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
            DropdownButtonFormField<String>(
                initialValue: _categoryChoice,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in ['Praise', 'Worship', 'Communion', 'Other'])
                    DropdownMenuItem(value: c, child: Text(c))
                ],
                onChanged: (value) => setState(() {
                      if (value == 'Other' && _categoryChoice != 'Other') {
                        _category.clear();
                      }
                      _categoryChoice = value!;
                    })),
            Visibility(
              visible: _categoryChoice == 'Other',
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _category,
                    decoration: const InputDecoration(labelText: 'Custom category'),
                    validator: SongValidation.requiredText,
                  ),
                ],
              ),
            ),
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
                          '${arrangement.bpm} BPM · ${arrangement.timeSignature}'),
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
            const SizedBox(height: 20),
            Text('Vocal Key Presets',
                style: Theme.of(context).textTheme.titleLarge),
            for (final v in _vocalists)...[
              const SizedBox(height: 16),
              Row(key: ObjectKey(v), children: [
                Expanded(
                    child: TextFormField(
                        controller: v.name,
                        decoration:
                            const InputDecoration(labelText: 'Vocalist'),
                        validator: SongValidation.requiredText)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                        controller: v.key,
                        decoration:
                            const InputDecoration(labelText: 'Preferred key'),
                        validator: SongValidation.key)),
                IconButton(
                    tooltip: 'Remove vocalist',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      setState(() => _vocalists.remove(v));
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => v.dispose());
                    }),
              ]),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
                onPressed: () => setState(() => _addPreset('', '')),
                icon: const Icon(Icons.add),
                label: const Text('Add Vocalist Preset')),
          ])),
    ));
  }
}

class _VocalistFields {
  _VocalistFields(String name, String key)
      : name = TextEditingController(text: name),
        key = TextEditingController(text: key);
  final TextEditingController name, key;
  void dispose() {
    name.dispose();
    key.dispose();
  }
}
