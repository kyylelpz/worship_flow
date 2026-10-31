import 'package:flutter/material.dart';
import '../data/song_validation.dart';
import '../screens/basic_chordpro_editor_screen.dart';

/// Canonical draft editing. Navigation returns text; the arrangement repository
/// owns persistence, so Phase 3B can replace the basic editor independently.
class ChordProSourceField extends StatelessWidget {
  const ChordProSourceField(
      {super.key, required this.controller, this.readOnly = false});
  final TextEditingController controller;
  final bool readOnly;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                  tooltip: 'Open ChordPro editor',
                  icon: const Icon(Icons.open_in_full),
                  onPressed: readOnly
                      ? null
                      : () async {
                          final text = await openChordProEditor(
                              context, controller.text);
                          if (text != null && context.mounted) {
                            controller.text = text;
                          }
                        })),
          TextFormField(
              readOnly: readOnly,
              controller: controller,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              minLines: 8,
              maxLines: 18,
              decoration: const InputDecoration(
                  labelText: 'ChordPro source',
                  helperText:
                      'Saved exactly as entered; no automatic rewriting.'),
              style: const TextStyle(fontFamily: 'monospace'),
              validator: SongValidation.requiredText),
        ],
      );
}
