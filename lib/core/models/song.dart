import 'arrangement.dart';
import 'vocalist_key.dart';

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.category,
    this.vocalistKeys = const [],
    required this.arrangements,
    required this.isFavorite,
  });

  final String id;
  final String title;
  final String artist;
  final String category;
  final List<VocalistKey> vocalistKeys;
  final List<Arrangement> arrangements;
  final bool isFavorite;

  Arrangement get primaryArrangement => arrangements.first;

  Song copyWith(
      {bool? isFavorite,
      String? title,
      String? artist,
      String? category,
      List<VocalistKey>? vocalistKeys,
      List<Arrangement>? arrangements}) {
    return Song(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      category: category ?? this.category,
      vocalistKeys: vocalistKeys ?? this.vocalistKeys,
      arrangements: arrangements ?? this.arrangements,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
