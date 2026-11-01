import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/arrangement.dart';
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
  late final _bpm =
      TextEditingController(text: '${widget.arrangement?.bpm ?? 80}');
  late final _meter =
      TextEditingController(text: widget.arrangement?.timeSignature ?? '4/4');
  late final _source =
      TextEditingController(text: widget.arrangement?.chordProSource ?? '');
  late final _reference =
      TextEditingController(text: widget.arrangement?.referenceLink ?? '');
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _reference, _bpm, _meter, _source]) {
      c.dispose();
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
        bpm: int.parse(_bpm.text),
        timeSignature: _meter.text,
        chordProSource: _source.text,
        referenceLink: _reference.text);
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
              TextFormField(
                  controller: _reference,
                  readOnly: !ref.watch(canManageSongsProvider),
                  decoration: const InputDecoration(
                      labelText: 'Reference link (optional)'),
                  validator: SongValidation.referenceLink),
              const SizedBox(height: 16),
              ChordProSourceField(
                  controller: _source,
                  readOnly: !ref.watch(canManageSongsProvider)),
            ])),
      );
}
