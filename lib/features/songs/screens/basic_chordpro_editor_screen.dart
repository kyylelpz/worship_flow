import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/arrangement.dart';
import '../../../core/models/chart_settings.dart';
import '../../../core/models/song.dart';
import '../../../core/models/vocalist_key.dart';
import '../../auth/providers/auth_providers.dart';
import '../../charts/data/chart_transformer.dart';
import '../../charts/models/chart_document.dart';
import '../../charts/models/chord_symbol.dart';
import '../../charts/widgets/chord_chart_view.dart';
import '../../profile/screens/chart_settings_screen.dart';
import '../providers/song_providers.dart';
import '../widgets/chordpro_editing_controller.dart';

/// Returns a source draft only; the parent owns all persistence.
Future<String?> openChordProEditor(BuildContext context, String source,
        {List<VocalistKey> vocalistKeys = const [],
        String? previewKey,
        String timeSignature = '4/4'}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ChordProEditorScreen(
            source: source,
            vocalistKeys: vocalistKeys,
            previewKey: previewKey,
            timeSignature: timeSignature)));

/// Compatibility name for callers of the original source editor.
typedef BasicChordProEditorScreen = ChordProEditorScreen;

class ChordProEditorScreen extends ConsumerStatefulWidget {
  const ChordProEditorScreen(
      {super.key,
      required this.source,
      this.vocalistKeys = const [],
      this.previewKey,
      this.timeSignature = '4/4'});
  final String source;
  final List<VocalistKey> vocalistKeys;
  final String? previewKey;
  final String timeSignature;
  @override
  ConsumerState<ChordProEditorScreen> createState() =>
      _ChordProEditorScreenState();
}

class _ChordProEditorScreenState extends ConsumerState<ChordProEditorScreen> {
  late final _source = ChordProEditingController(text: widget.source);
  late final _key = TextEditingController(
      text: widget.previewKey ??
          widget.vocalistKeys
              .where((v) => MusicalKey.tryParse(v.key) != null)
              .firstOrNull
              ?.key ??
          '');
  late final _group = ref.read(selectedGroupIdProvider);
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _preview = false, _allowExit = false, _confirming = false;
  bool _restoreFocus = false;
  bool? _nashville;
  double _editorOffset = 0;
  ChartDocument? _document;
  String? _previewError, _parsedSource, _parsedKey;

  bool get _canEdit =>
      ref.read(canManageSongsProvider) &&
      ref.read(selectedGroupIdProvider) == _group;

  @override
  void dispose() {
    _source.dispose();
    _key.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _pop([String? result]) {
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _back() async {
    if (_confirming || _allowExit) return;
    if (_source.text == widget.source) {
      _pop();
      return;
    }
    _confirming = true;
    final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Discard source changes?'),
                content: const Text(
                    'The source draft has not been returned to the arrangement.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep editing')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Discard'))
                ]));
    _confirming = false;
    if (mounted && discard == true) _pop();
  }

  void _save() {
    if (!_canEdit) return;
    if (_source.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ChordPro source is required.')));
      return;
    }
    _pop(_source.text);
  }

  void _parsePreview() {
    if (_parsedSource == _source.text && _parsedKey == _key.text) return;
    _parsedSource = _source.text;
    _parsedKey = _key.text;
    _document = null;
    _previewError = null;
    if (MusicalKey.tryParse(_key.text) == null) {
      _previewError =
          'Choose a preview performance key, such as E or F#m. Source {key:} is not required for numbered chords.';
      return;
    }
    final arrangement = Arrangement(
        id: 'preview-arrangement',
        name: 'Preview',
        bpm: 80,
        timeSignature: widget.timeSignature,
        chordProSource: _source.text);
    final song = Song(
        id: 'preview-song',
        title: 'Chart preview',
        artist: '',
        category: '',
        arrangements: [arrangement],
        isFavorite: false);
    try {
      _document = const ChartTransformer()
          .prepare(
              song: song,
              arrangement: arrangement,
              previewKey: _key.text,
              settings: const ChartSettings())
          .document;
    } on ArgumentError catch (error) {
      _previewError = '${error.message}';
    }
  }

  void _togglePreview() {
    if (!_preview) {
      _editorOffset = _scroll.hasClients ? _scroll.offset : 0;
      _restoreFocus = _focus.hasFocus;
      _focus.unfocus();
      _parsePreview();
    }
    setState(() => _preview = !_preview);
    if (!_preview) {
      if (_restoreFocus && _canEdit) _focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll
              .jumpTo(_editorOffset.clamp(0, _scroll.position.maxScrollExtent));
        }
      });
    }
  }

  void _insert(String before, String after) {
    if (!_canEdit) return;
    _source.insert(before, after);
    _focus.requestFocus();
  }

  Widget _shortcuts(bool canEdit) => SafeArea(
      top: false,
      child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: SingleChildScrollView(
              key: const ValueKey('source-shortcuts'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                for (final shortcut in const <(String, String, String)>[
                  ('[Chord]', '[', ']'),
                  ('Section', '{section: ', '}'),
                  ('Verse', '{start_of_verse: ', '}'),
                  ('End verse', '{end_of_verse}', ''),
                  ('Chorus', '{start_of_chorus}', ''),
                  ('End chorus', '{end_of_chorus}', ''),
                  ('Key', '{key: ', '}'),
                  ('Tempo', '{tempo: ', '}'),
                  ('Time', '{time: ', '}'),
                  ('Grid', '{start_of_grid: ', '}'),
                  ('End grid', '{end_of_grid}', ''),
                  ('Bar', ' | ', ''),
                  ('Sustain', ' - ', ''),
                ])
                  Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48)),
                          onPressed: canEdit
                              ? () => _insert(shortcut.$2, shortcut.$3)
                              : null,
                          child: Text(shortcut.$1))),
              ]))));

  Widget _previewPane(ChartSettings settings) {
    final effective =
        settings.copyWith(useNashville: _nashville ?? settings.useNashville);
    return Column(children: [
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            SizedBox(
                width: 160,
                child: TextField(
                    key: const ValueKey('preview-key'),
                    controller: _key,
                    decoration: const InputDecoration(labelText: 'Preview key'),
                    onSubmitted: (_) => setState(_parsePreview))),
            IconButton(
                tooltip: 'Apply preview key',
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(_parsePreview);
                },
                icon: const Icon(Icons.check)),
            for (final preset in widget.vocalistKeys
                .where((v) => MusicalKey.tryParse(v.key) != null))
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                      label: Text('${preset.vocalistName} · ${preset.key}'),
                      onPressed: () {
                        _key.text = preset.key;
                        setState(_parsePreview);
                      })),
            ChoiceChip(
                label: const Text('Standard'),
                selected: !effective.useNashville,
                onSelected: (_) => setState(() => _nashville = false)),
            const SizedBox(width: 8),
            ChoiceChip(
                label: const Text('Nashville'),
                selected: effective.useNashville,
                onSelected: (_) => setState(() => _nashville = true)),
          ])),
      Expanded(
          child: _document == null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Text(_previewError ??
                      'Open Preview to render the current draft.'))
              : ChordChartView(
                  chart:
                      const ChartTransformer().display(_document!, effective),
                  settings: effective)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(canManageSongsProvider) &&
        ref.watch(selectedGroupIdProvider) == _group;
    final settings = ref.watch(chartSettingsProvider);
    final theme = Theme.of(context);
    return PopScope(
        canPop: _allowExit,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop) await _back();
        },
        child: Scaffold(
          appBar: AppBar(
              leading: IconButton(
                  tooltip: 'Back',
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back)),
              title: const Text('ChordPro',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _source,
                    builder: (_, value, child) => Row(children: [
                          IconButton(
                              tooltip: 'Undo',
                              onPressed: canEdit && !_preview && _source.canUndo
                                  ? _source.undo
                                  : null,
                              icon: const Icon(Icons.undo)),
                          IconButton(
                              tooltip: 'Redo',
                              onPressed: canEdit && !_preview && _source.canRedo
                                  ? _source.redo
                                  : null,
                              icon: const Icon(Icons.redo)),
                        ])),
                IconButton(
                    tooltip: _preview ? 'Edit source' : 'Preview',
                    onPressed: _togglePreview,
                    icon: Icon(
                        _preview ? Icons.code : Icons.visibility_outlined)),
                IconButton(
                    tooltip: 'Save',
                    onPressed: canEdit ? _save : null,
                    icon: const Icon(Icons.save_outlined)),
              ]),
          body: SafeArea(
              top: false,
              bottom: _preview,
              child: Column(children: [
                if (!canEdit)
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                          'Read only: song management permission in the original group is required.')),
                Expanded(
                    child: IndexedStack(index: _preview ? 1 : 0, children: [
                  Column(children: [
                    Expanded(
                        child: Actions(
                            actions: {
                          UndoTextIntent:
                              CallbackAction<UndoTextIntent>(onInvoke: (_) {
                            if (canEdit) _source.undo();
                            return null;
                          }),
                          RedoTextIntent:
                              CallbackAction<RedoTextIntent>(onInvoke: (_) {
                            if (canEdit) _source.redo();
                            return null;
                          }),
                        },
                            child: TextFormField(
                                key: const ValueKey('chordpro-source'),
                                controller: _source,
                                focusNode: _focus,
                                scrollController: _scroll,
                                readOnly: !canEdit,
                                expands: true,
                                minLines: null,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                autocorrect: false,
                                enableSuggestions: false,
                                smartDashesType: SmartDashesType.disabled,
                                smartQuotesType: SmartQuotesType.disabled,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: const InputDecoration(
                                    labelText: 'Canonical ChordPro',
                                    alignLabelWithHint: true,
                                    contentPadding: EdgeInsets.all(16),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none),
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 15,
                                    height: 1.5,
                                    color: theme.colorScheme.onSurface)))),
                    _shortcuts(canEdit),
                  ]),
                  _previewPane(settings),
                ])),
              ])),
        ));
  }
}
