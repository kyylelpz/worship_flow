import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/song_validation.dart';
import '../providers/song_providers.dart';

/// Typed navigation boundary for Phase 3B. This basic editor returns draft text;
/// the arrangement repository remains the only persistence/authorization layer.
Future<String?> openChordProEditor(BuildContext context, String source) =>
    Navigator.of(context).push<String>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BasicChordProEditorScreen(source: source)));

class BasicChordProEditorScreen extends ConsumerStatefulWidget {
  const BasicChordProEditorScreen({super.key, required this.source});
  final String source;
  @override
  ConsumerState<BasicChordProEditorScreen> createState() =>
      _BasicChordProEditorScreenState();
}

class _BasicChordProEditorScreenState
    extends ConsumerState<BasicChordProEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.source);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ChordPro Source'), actions: [
          TextButton(
              onPressed: ref.watch(canManageSongsProvider)
                  ? () {
                      if (_form.currentState!.validate()) {
                        Navigator.pop(context, _controller.text);
                      }
                    }
                  : null,
              child: const Text('Use Source')),
        ]),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              TextFormField(
                  readOnly: !ref.watch(canManageSongsProvider),
                  controller: _controller,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  minLines: 15,
                  maxLines: null,
                  decoration: const InputDecoration(
                      labelText: 'Canonical ChordPro',
                      helperText: 'No automatic formatting or rewriting.'),
                  style: const TextStyle(fontFamily: 'monospace'),
                  validator: SongValidation.requiredText)
            ])),
      );
}
