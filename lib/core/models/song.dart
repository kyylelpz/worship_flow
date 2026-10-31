import 'arrangement.dart';

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.category,
    required this.defaultKey,
    required this.arrangements,
    required this.isFavorite,
  });

  final String id;
  final String title;
  final String artist;
  final String category;
  final String defaultKey;
  final List<Arrangement> arrangements;
  final bool isFavorite;

  Arrangement get primaryArrangement => arrangements.first;

  Song copyWith(
      {bool? isFavorite,
      String? title,
      String? artist,
      String? category,
      String? defaultKey,
      List<Arrangement>? arrangements}) {
    return Song(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      category: category ?? this.category,
      defaultKey: defaultKey ?? this.defaultKey,
      arrangements: arrangements ?? this.arrangements,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
