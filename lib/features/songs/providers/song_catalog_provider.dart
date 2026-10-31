import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_song_repository.dart';

final songCatalogProvider = Provider<InMemorySongCatalog>((ref) {
  final catalog = InMemorySongCatalog();
  ref.onDispose(catalog.dispose);
  return catalog;
});
