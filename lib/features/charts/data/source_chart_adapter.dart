/// Temporary, display-only grouping of source lines. No transposition,
/// Nashville conversion, or musical interpretation is performed.
class SourceChartSection {
  const SourceChartSection(this.label, this.source);
  final String label;
  final String source;
}

List<SourceChartSection> sourceChartSections(String source) {
  final sections = <SourceChartSection>[];
  var label = 'Chart';
  var lines = <String>[];
  final marker = RegExp(r'^\s*\{section:\s*(.*?)\}\s*$', caseSensitive: false);
  void flush() {
    final text = lines.join('\n').trim();
    if (text.isNotEmpty) sections.add(SourceChartSection(label, text));
    lines = [];
  }

  for (final line in source.split('\n')) {
    final match = marker.firstMatch(line);
    if (match == null) {
      lines.add(line);
    } else {
      flush();
      label = match.group(1)!.trim();
      if (label.isEmpty) label = 'Section';
    }
  }
  flush();
  return sections;
}
