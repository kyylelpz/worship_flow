import '../../../core/models/song.dart';
import '../../../core/models/arrangement.dart';
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
    final names = <String>{};
    for (final preset in value.vocalistKeys) {
      _check(requiredText(preset.vocalistName));
      _check(key(preset.key));
      if (!names.add(preset.vocalistName.trim().toLowerCase())) {
        throw const SongRepositoryException('Use one key preset per vocalist.');
      }
    }
  }

  static String? referenceLink(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
            const ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? null
        : 'Enter a valid http or https URL.';
  }

  static void arrangement(Arrangement value) {
    _check(requiredText(value.name));
    _check(bpm('${value.bpm}'));
    _check(meter(value.timeSignature));
    _check(requiredText(value.chordProSource));
    _check(referenceLink(value.referenceLink));
  }
}
