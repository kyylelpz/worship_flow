import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/arrangement.dart';
import '../../../core/models/vocalist_key.dart';
import '../data/song_validation.dart';
import '../providers/song_providers.dart';
import '../widgets/chordpro_source_field.dart';

class ArrangementEditorScreen extends ConsumerStatefulWidget {
  const ArrangementEditorScreen({super.key, this.arrangement});
  final Arrangement? arrangement;
  @override
  ConsumerState<ArrangementEditorScreen> createState() =>
      _ArrangementEditorScreenState();
}

class _ArrangementEditorScreenState
    extends ConsumerState<ArrangementEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.arrangement?.name ?? 'Full Band');
  late final _key =
      TextEditingController(text: widget.arrangement?.performanceKey ?? 'G');
  late final _bpm =
      TextEditingController(text: '${widget.arrangement?.bpm ?? 80}');
  late final _meter =
      TextEditingController(text: widget.arrangement?.timeSignature ?? '4/4');
  late final _source =
      TextEditingController(text: widget.arrangement?.chordProSource ?? '');
  late final List<_VocalistFields> _vocalists = [
    for (final v in widget.arrangement?.vocalistKeys ?? <VocalistKey>[])
      _VocalistFields(v.vocalistName, v.key)
  ];
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _key, _bpm, _meter, _source]) {
      c.dispose();
    }
    for (final v in _vocalists) {
      v.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!ref.read(canManageSongsProvider)) {
      setState(() => _error = 'Song management permission is required.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    final value = Arrangement(
        id: widget.arrangement?.id ?? const Uuid().v4(),
        name: _name.text,
        performanceKey: _key.text,
        bpm: int.parse(_bpm.text),
        timeSignature: _meter.text,
        chordProSource: _source.text,
        vocalistKeys: [
          for (final v in _vocalists)
            VocalistKey(vocalistName: v.name.text, key: v.key.text)
        ]);
    try {
      SongValidation.arrangement(value);
      Navigator.pop(context, value);
    } catch (error) {
      setState(() => _error = '$error');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.arrangement == null
                ? 'New Arrangement'
                : 'Edit Arrangement'),
            actions: [
              TextButton(
                  onPressed: ref.watch(canManageSongsProvider) ? _save : null,
                  child: const Text('Save Arrangement'))
            ]),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              TextFormField(
                  readOnly: !ref.watch(canManageSongsProvider),
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: 'Arrangement name'),
                  validator: SongValidation.requiredText),
              const SizedBox(height: 16),
              TextFormField(
                  readOnly: !ref.watch(canManageSongsProvider),
                  controller: _key,
                  decoration:
                      const InputDecoration(labelText: 'Performance key'),
                  validator: SongValidation.key),
              const SizedBox(height: 16),
              TextFormField(
                  readOnly: !ref.watch(canManageSongsProvider),
                  controller: _bpm,
                  decoration: const InputDecoration(labelText: 'BPM'),
                  keyboardType: TextInputType.number,
                  validator: SongValidation.bpm),
              const SizedBox(height: 16),
              TextFormField(
                  readOnly: !ref.watch(canManageSongsProvider),
                  controller: _meter,
                  decoration:
                      const InputDecoration(labelText: 'Time signature'),
                  validator: SongValidation.meter),
              const SizedBox(height: 16),
              Text('Vocalist key presets',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              for (final v in _vocalists)
                Row(key: ObjectKey(v), children: [
                  Expanded(
                      child: TextFormField(
                          readOnly: !ref.watch(canManageSongsProvider),
                          controller: v.name,
                          decoration:
                              const InputDecoration(labelText: 'Vocalist'),
                          validator: SongValidation.requiredText)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextFormField(
                          readOnly: !ref.watch(canManageSongsProvider),
                          controller: v.key,
                          decoration:
                              const InputDecoration(labelText: 'Vocalist key'),
                          validator: SongValidation.key)),
                  IconButton(
                      tooltip: 'Remove vocalist',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: ref.watch(canManageSongsProvider)
                          ? () {
                              setState(() => _vocalists.remove(v));
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) => v.dispose());
                            }
                          : null),
                  const SizedBox(height: 8),
                ]),
              TextButton.icon(
                  onPressed: ref.watch(canManageSongsProvider)
                      ? () => setState(
                          () => _vocalists.add(_VocalistFields('', 'G')))
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add vocalist preset')),
              ChordProSourceField(
                  controller: _source,
                  readOnly: !ref.watch(canManageSongsProvider)),
            ])),
      );
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
