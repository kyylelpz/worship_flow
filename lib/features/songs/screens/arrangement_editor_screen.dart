import '../../../core/models/edit_conflict.dart';
import '../../../core/widgets/edit_conflict_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/arrangement.dart';
import '../../../core/models/vocalist_key.dart';
import '../data/song_validation.dart';
import '../providers/song_providers.dart';
import '../widgets/chordpro_source_field.dart';

class ArrangementEditorScreen extends ConsumerStatefulWidget {
  const ArrangementEditorScreen(
      {super.key,
      this.arrangement,
      this.vocalistKeys = const [],
      this.onSave,
      this.onReload});
  final Arrangement? arrangement;
  final Future<void> Function(Arrangement value, Arrangement? expected)? onSave;
  final Future<Arrangement?> Function()? onReload;
  final List<VocalistKey> vocalistKeys;
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
  bool _saving = false, _deleted = false;
  late Arrangement? _expected = widget.arrangement;
  @override
  void dispose() {
    for (final c in [_name, _reference, _bpm, _meter, _source]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _deleted) return;
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
      setState(() => _saving = true);
      await widget.onSave?.call(value, _expected);
      if (mounted) Navigator.pop(context, value);
    } on EditConflict catch (conflict) {
      if (mounted &&
          await confirmConflictReload(context, conflict) &&
          mounted) {
        try {
          final latest = await widget.onReload?.call();
          if (!mounted) return;
          setState(() {
            _expected = latest;
            _deleted = latest == null;
            _error = latest == null
                ? 'Arrangement no longer exists. Close this editor.'
                : null;
            if (latest != null) {
              _name.text = latest.name;
              _bpm.text = '${latest.bpm}';
              _meter.text = latest.timeSignature;
              _source.text = latest.chordProSource;
              _reference.text = latest.referenceLink;
            }
          });
        } catch (error) {
          if (mounted) {
            setState(
                () => _error = 'Could not reload. Your edits are kept: $error');
          }
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.arrangement == null
                ? 'New Arrangement'
                : 'Edit Arrangement'),
            actions: [
              TextButton(
                  onPressed:
                      ref.watch(canManageSongsProvider) && !_saving && !_deleted
                          ? _save
                          : null,
                  child: const Text('Save Arrangement'))
            ]),
        body: AbsorbPointer(
            absorbing: _saving,
            child: Form(
                key: _form,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
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
                      onChanged: (_) => setState(() {}),
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
                      vocalistKeys: widget.vocalistKeys,
                      timeSignature: _meter.text,
                      readOnly: !ref.watch(canManageSongsProvider)),
                ]))),
      ));
}
