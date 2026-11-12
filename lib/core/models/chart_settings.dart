class ChartSettings {
  const ChartSettings({
    this.lyricsFontSize = 16,
    this.chordsFontSize = 20,
    this.sectionHeaderFontSize = 22,
    this.globalScale = 1.0,
    this.lineSpacing = 1.4,
    this.chordSpacing = 8,
    this.lightChordColor = ChordColorPreset.themeDefault,
    this.darkChordColor = ChordColorPreset.themeDefault,
    this.chartWidth = 720,
    this.useNashville = false,
    this.displayMode = ChartDisplayMode.lyricsAndChords,
  });

  final double lyricsFontSize;
  final double chordsFontSize;
  final double sectionHeaderFontSize;
  final double globalScale;
  final double lineSpacing;
  final double chordSpacing;
  final ChordColorPreset lightChordColor;
  final ChordColorPreset darkChordColor;
  final double chartWidth;
  final bool useNashville;
  final ChartDisplayMode displayMode;

  ChordColorPreset chordColorFor(bool dark) {
    final saved = dark ? darkChordColor : lightChordColor;
    return saved == ChordColorPreset.themeDefault
        ? ChordColorPreset.defaultFor(dark)
        : saved;
  }

  ChartSettings copyWith({
    double? lyricsFontSize,
    double? chordsFontSize,
    double? sectionHeaderFontSize,
    double? globalScale,
    double? lineSpacing,
    double? chordSpacing,
    ChordColorPreset? lightChordColor,
    ChordColorPreset? darkChordColor,
    double? chartWidth,
    bool? useNashville,
    ChartDisplayMode? displayMode,
  }) {
    return ChartSettings(
      lyricsFontSize: lyricsFontSize ?? this.lyricsFontSize,
      chordsFontSize: chordsFontSize ?? this.chordsFontSize,
      sectionHeaderFontSize:
          sectionHeaderFontSize ?? this.sectionHeaderFontSize,
      globalScale: globalScale ?? this.globalScale,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      chordSpacing: chordSpacing ?? this.chordSpacing,
      lightChordColor: lightChordColor ?? this.lightChordColor,
      darkChordColor: darkChordColor ?? this.darkChordColor,
      chartWidth: chartWidth ?? this.chartWidth,
      useNashville: useNashville ?? this.useNashville,
      displayMode: displayMode ?? this.displayMode,
    );
  }
}

enum ChordColorPreset {
  themeDefault('Default', null, null),
  navy('Navy', 0xFF203B70, false),
  royalBlue('Royal Blue', 0xFF2455C7, false),
  purple('Purple', 0xFF6941B8, false),
  teal('Teal', 0xFF006F70, false),
  burgundy('Burgundy', 0xFF9B2848, false),
  charcoal('Charcoal', 0xFF263445, false),
  skyBlue('Sky Blue', 0xFF8CB8FF, true),
  softYellow('Soft Yellow', 0xFFF6E879, true),
  mint('Mint', 0xFF7FE2BA, true),
  lavender('Lavender', 0xFFC5ADFF, true),
  peach('Peach', 0xFFFFB48E, true),
  white('White', 0xFFF1F5FF, true);

  const ChordColorPreset(this.label, this.argb, this.dark);
  final String label;
  final int? argb;
  final bool? dark;

  static ChordColorPreset defaultFor(bool dark) =>
      dark ? skyBlue : themeDefault;

  static Iterable<ChordColorPreset> forTheme(bool dark) =>
      values.where((preset) => preset.dark == dark);

  static ChordColorPreset fromStoredName(Object? name, {required bool dark}) =>
      forTheme(dark).where((preset) => preset.name == name).firstOrNull ??
      themeDefault;
}

enum ChartDisplayMode {
  lyricsAndChords('Lyrics + Chords'),
  chordsOnly('Chords'),
  lyricsOnly('Lyrics');

  const ChartDisplayMode(this.label);
  final String label;
}
