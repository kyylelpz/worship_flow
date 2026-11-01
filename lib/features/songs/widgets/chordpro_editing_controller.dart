import 'package:flutter/material.dart';

import '../../charts/models/chord_symbol.dart';

enum ChordProSyntax { text, directive, metadata, chord }

class _Run {
  const _Run(this.text, this.syntax);
  final String text;
  final ChordProSyntax syntax;
}

/// Source-only highlighting and bounded, selection-aware editing history.
/// No chart parsing or source normalization occurs here.
class ChordProEditingController extends TextEditingController {
  ChordProEditingController({super.text});

  final _undo = <TextEditingValue>[];
  final _redo = <TextEditingValue>[];
  bool _restoring = false;
  String? _cachedText;
  Map<String, List<_Run>> _lines = {};
  List<_Run> _runs = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _remember(List<TextEditingValue> history, TextEditingValue entry) {
    history.add(entry.copyWith(composing: TextRange.empty));
    var size = history.fold<int>(0, (n, v) => n + v.text.length);
    while (history.length > 1 && (history.length > 100 || size > 2000000)) {
      size -= history.removeAt(0).text.length;
    }
  }

  @override
  set value(TextEditingValue next) {
    if (!_restoring && next.text != value.text) {
      // Treat an IME composition as one edit, not a series of partial syllables.
      if (!value.composing.isValid || value.composing.isCollapsed) {
        _remember(_undo, value);
      }
      _redo.clear();
    }
    super.value = next;
  }

  void _restore(List<TextEditingValue> from, List<TextEditingValue> to) {
    if (from.isEmpty) return;
    _remember(to, value);
    _restoring = true;
    try {
      value = from.removeLast();
    } finally {
      _restoring = false;
    }
  }

  void undo() => _restore(_undo, _redo);
  void redo() => _restore(_redo, _undo);

  /// Wrap a selection, or insert a pair with the cursor inside it.
  void insert(String before, [String after = '']) {
    // A toolbar edit is a separate transaction from any active composition.
    clearComposing();
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = after.isEmpty ? '' : text.substring(start, end);
    value = TextEditingValue(
        text: text.replaceRange(start, end, '$before$selected$after'),
        selection: TextSelection.collapsed(
            offset: start + before.length + selected.length));
  }

  static const _metadata = {
    'title',
    't',
    'subtitle',
    'st',
    'artist',
    'author',
    'composer',
    'lyricist',
    'album',
    'copyright',
    'year',
    'key',
    'k',
    'capo',
    'tempo',
    'time',
    'duration',
    'grid_subdivision'
  };
  static final _tokens = RegExp(r'\{[\w-]+(?::[^{}\r\n]*)?\}|\[[^\[\]\r\n]+\]');
  static final _words = RegExp(r'[^\s|:]+');
  static const _syntaxKey = MusicalKey(NoteName('C', 0));
  static bool _isChord(String token) =>
      ChordSymbol.tryParse(token) != null ||
      ChordSymbol.tryParseNumbered(token, _syntaxKey) != null;

  List<_Run> _highlightLine(String line) {
    final result = <_Run>[];
    // Whole instrumental rows may mix bracketed and bare chords. Ordinary
    // lyric words never acquire chord colors just because they contain a root.
    final words = _words.allMatches(line).toList();
    String name(String word) => word.startsWith('[') && word.endsWith(']')
        ? word.substring(1, word.length - 1)
        : word;
    const markers = {'-', '/', '.', '%', 'NC', 'N.C.'};
    if (words.isNotEmpty &&
        words.every((m) => _isChord(name(m[0]!)) || markers.contains(m[0]))) {
      var start = 0;
      for (final word in words) {
        result
            .add(_Run(line.substring(start, word.start), ChordProSyntax.text));
        result.add(_Run(
            word[0]!,
            _isChord(name(word[0]!))
                ? ChordProSyntax.chord
                : ChordProSyntax.text));
        start = word.end;
      }
      result.add(_Run(line.substring(start), ChordProSyntax.text));
      return result;
    }
    var cursor = 0;
    for (final match in _tokens.allMatches(line)) {
      if (cursor < match.start) {
        result.add(
            _Run(line.substring(cursor, match.start), ChordProSyntax.text));
      }
      final token = match[0]!;
      if (token.startsWith('{')) {
        final directive = RegExp(r'^\{([\w-]+):').firstMatch(token);
        if (directive != null &&
            _metadata.contains(directive[1]!.toLowerCase())) {
          result.add(_Run(
              token.substring(0, directive.end), ChordProSyntax.directive));
          result.add(_Run(token.substring(directive.end, token.length - 1),
              ChordProSyntax.metadata));
          result.add(const _Run('}', ChordProSyntax.directive));
        } else {
          result.add(_Run(token, ChordProSyntax.directive));
        }
      } else {
        result.add(_Run(
            token,
            _isChord(token.substring(1, token.length - 1))
                ? ChordProSyntax.chord
                : ChordProSyntax.text));
      }
      cursor = match.end;
    }
    if (cursor < line.length) {
      result.add(_Run(line.substring(cursor), ChordProSyntax.text));
    }
    return result;
  }

  void _highlight() {
    if (_cachedText == text) return;
    final next = <String, List<_Run>>{};
    _runs = [];
    for (final line in RegExp(r'[^\r\n]*(?:\r\n|\r|\n|$)').allMatches(text)) {
      final content = line[0]!;
      if (content.isEmpty) continue;
      final runs = next.putIfAbsent(
          content, () => _lines[content] ?? _highlightLine(content));
      _runs.addAll(runs);
    }
    _lines = next;
    _cachedText = text;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    _highlight();
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color? color(ChordProSyntax syntax) => switch (syntax) {
          ChordProSyntax.text => null,
          ChordProSyntax.directive =>
            dark ? Colors.greenAccent.shade100 : Colors.green.shade800,
          ChordProSyntax.metadata =>
            dark ? const Color(0xffff8be0) : const Color(0xffa00080),
          ChordProSyntax.chord =>
            dark ? Colors.tealAccent.shade100 : Colors.teal.shade800,
        };
    final composing = withComposing &&
            value.isComposingRangeValid &&
            !value.composing.isCollapsed
        ? value.composing
        : TextRange.empty;
    var offset = 0;
    final spans = <TextSpan>[];
    for (final run in _runs) {
      final end = offset + run.text.length;
      final boundaries = <int>{
        offset,
        end,
        if (composing.start > offset && composing.start < end) composing.start,
        if (composing.end > offset && composing.end < end) composing.end
      }.toList()
        ..sort();
      for (var i = 0; i < boundaries.length - 1; i++) {
        final start = boundaries[i];
        spans.add(TextSpan(
            text:
                run.text.substring(start - offset, boundaries[i + 1] - offset),
            style: TextStyle(
                color: color(run.syntax),
                decoration: composing.isValid &&
                        start >= composing.start &&
                        start < composing.end
                    ? TextDecoration.underline
                    : null)));
      }
      offset = end;
    }
    return TextSpan(style: style, children: spans);
  }
}
