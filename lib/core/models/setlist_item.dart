class SetlistItem {
  const SetlistItem({
    required this.songId,
    required this.arrangementId,
    required this.performanceKey,
    this.vocalistName,
  });

  final String songId;
  final String arrangementId;
  final String performanceKey;
  final String? vocalistName;

  SetlistItem copyWith(
      {String? arrangementId,
      String? performanceKey,
      String? vocalistName,
      bool clearVocalist = false}) {
    return SetlistItem(
      songId: songId,
      arrangementId: arrangementId ?? this.arrangementId,
      performanceKey: performanceKey ?? this.performanceKey,
      vocalistName: clearVocalist ? null : vocalistName ?? this.vocalistName,
    );
  }
}
