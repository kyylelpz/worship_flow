class SetlistItem {
  const SetlistItem({
    required this.songId,
    required this.arrangementId,
    required this.performanceKey,
  });

  final String songId;
  final String arrangementId;
  final String performanceKey;

  SetlistItem copyWith({String? arrangementId, String? performanceKey}) {
    return SetlistItem(
      songId: songId,
      arrangementId: arrangementId ?? this.arrangementId,
      performanceKey: performanceKey ?? this.performanceKey,
    );
  }
}
