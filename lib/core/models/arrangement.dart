import 'vocalist_key.dart';

class Arrangement {
  const Arrangement({
    required this.id,
    required this.name,
    required this.performanceKey,
    required this.bpm,
    required this.timeSignature,
    required this.chordProSource,
    required this.vocalistKeys,
  });

  final String id;
  final String name;
  final String performanceKey;
  final int bpm;
  final String timeSignature;
  final String chordProSource;
  final List<VocalistKey> vocalistKeys;
}
