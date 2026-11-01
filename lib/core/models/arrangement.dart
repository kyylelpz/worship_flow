class Arrangement {
  const Arrangement({
    required this.id,
    required this.name,
    required this.bpm,
    required this.timeSignature,
    required this.chordProSource,
    this.referenceLink = '',
  });

  final String id;
  final String name;
  final int bpm;
  final String timeSignature;
  final String chordProSource;
  final String referenceLink;
  Arrangement copyWith(
          {String? name,
          int? bpm,
          String? timeSignature,
          String? chordProSource,
          String? referenceLink}) =>
      Arrangement(
          id: id,
          name: name ?? this.name,
          bpm: bpm ?? this.bpm,
          timeSignature: timeSignature ?? this.timeSignature,
          chordProSource: chordProSource ?? this.chordProSource,
          referenceLink: referenceLink ?? this.referenceLink);
}
