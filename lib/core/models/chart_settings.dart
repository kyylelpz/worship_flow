class ChartSettings {
  const ChartSettings({
    this.lyricsFontSize = 16,
    this.chordsFontSize = 20,
    this.sectionHeaderFontSize = 22,
    this.globalScale = 1.0,
    this.lineSpacing = 1.4,
    this.chordSpacing = 8,
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
  final double chartWidth;
  final bool useNashville;
  final ChartDisplayMode displayMode;

  ChartSettings copyWith({
    double? lyricsFontSize,
    double? chordsFontSize,
    double? sectionHeaderFontSize,
    double? globalScale,
    double? lineSpacing,
    double? chordSpacing,
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
      chartWidth: chartWidth ?? this.chartWidth,
      useNashville: useNashville ?? this.useNashville,
      displayMode: displayMode ?? this.displayMode,
    );
  }
}

enum ChartDisplayMode {
  lyricsAndChords('Lyrics + Chords'),
  chordsOnly('Chords'),
  lyricsOnly('Lyrics');

  const ChartDisplayMode(this.label);
  final String label;
}
