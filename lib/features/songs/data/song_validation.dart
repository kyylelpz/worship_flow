import '../../../core/models/song.dart';
import '../../../core/models/arrangement.dart';
import '../../charts/data/chordpro_parser.dart';
import '../../charts/models/chord_symbol.dart';
import 'song_repository.dart';

abstract final class SongValidation {
  static String? requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'Required.' : null;
  static String? key(String? value) => MusicalKey.tryParse(value ?? '') == null
      ? 'Enter a major/minor key, e.g. G, Bb or F#m.'
      : null;
  static String? bpm(String? value) {
    final number = int.tryParse(value ?? '');
    return number == null || number < 1 || number > 400
        ? 'BPM must be a whole number from 1 to 400.'
        : null;
  }

  static String? meter(String? value) =>
      const ['3/4', '4/4', '6/8'].contains(value?.trim())
          ? null
          : 'Supported time signatures: 3/4, 4/4, 6/8.';
  static void _check(String? message) {
    if (message != null) throw SongRepositoryException(message);
  }

  static void song(Song value) {
    _check(requiredText(value.title));
    _check(requiredText(value.artist));
    _check(requiredText(value.category));
    _check(key(value.defaultKey));
  }

  static void arrangement(Arrangement value) {
    _check(requiredText(value.name));
    _check(key(value.performanceKey));
    _check(bpm('${value.bpm}'));
    _check(meter(value.timeSignature));
    _check(requiredText(value.chordProSource));
    final sourceKey = const ChordProParser().parse(value.chordProSource).key;
    if (sourceKey != null &&
        sourceKey.isMinor !=
            MusicalKey.tryParse(value.performanceKey)!.isMinor) {
      throw const SongRepositoryException(
          'Source key and performance key must use the same major/minor mode.');
    }
    final names = <String>{};
    for (final preset in value.vocalistKeys) {
      _check(requiredText(preset.vocalistName));
      _check(key(preset.key));
      if (MusicalKey.tryParse(preset.key)!.isMinor !=
          MusicalKey.tryParse(value.performanceKey)!.isMinor) {
        throw const SongRepositoryException(
            'Vocalist keys must use the arrangement major/minor mode.');
      }
      if (!names.add(preset.vocalistName.trim().toLowerCase())) {
        throw const SongRepositoryException('Use one key preset per vocalist.');
      }
    }
  }
}
