/// Pitch spelling is retained independently of its pitch class.
class NoteName {
  const NoteName(this.letter, this.accidental);
  final String letter;
  final int accidental;
  static const letters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  static const _pitches = [0, 2, 4, 5, 7, 9, 11];
  int get pitch => (_pitches[letters.indexOf(letter)] + accidental) % 12;
  String get name =>
      '$letter${accidental < 0 ? 'b' * -accidental : '#' * accidental}';

  static NoteName? tryParse(String text) {
    final match = RegExp(r'^([A-G])([#b♯♭]{0,2})$').firstMatch(text);
    if (match == null) return null;
    var accidental = 0;
    for (final rune in match[2]!.runes) {
      accidental += rune == 35 || rune == 0x266f ? 1 : -1;
    }
    return NoteName(match[1]!, accidental);
  }
}

class MusicalKey {
  const MusicalKey(this.tonic, {this.isMinor = false});
  final NoteName tonic;
  final bool isMinor;
  List<int> get intervals =>
      isMinor ? const [0, 2, 3, 5, 7, 8, 10] : const [0, 2, 4, 5, 7, 9, 11];
  String get name => '${tonic.name}${isMinor ? 'm' : ''}';

  static MusicalKey? tryParse(String text) {
    final match = RegExp(r'^([A-G][#b♯♭]{0,2})\s*(m|min|minor|maj|major)?$')
        .firstMatch(text.trim());
    if (match == null) return null;
    return MusicalKey(NoteName.tryParse(match[1]!)!,
        isMinor: const ['m', 'min', 'minor'].contains(match[2]));
  }

  /// Choose conventional signatures for an offset without an explicit target.
  MusicalKey transposed(int semitones) {
    final pitch = (tonic.pitch + semitones) % 12;
    final names = isMinor
        ? const [
            'C',
            'C#',
            'D',
            'Eb',
            'E',
            'F',
            'F#',
            'G',
            'G#',
            'A',
            'Bb',
            'B'
          ]
        : const [
            'C',
            'Db',
            'D',
            'Eb',
            'E',
            'F',
            'F#',
            'G',
            'Ab',
            'A',
            'Bb',
            'B'
          ];
    return MusicalKey(NoteName.tryParse(names[pitch])!, isMinor: isMinor);
  }

  bool get prefersFlats {
    if (tonic.accidental != 0) return tonic.accidental < 0;
    // Minor uses the signature of its relative major.
    final signaturePitch = (tonic.pitch + (isMinor ? 3 : 0)) % 12;
    return const [1, 3, 5, 8, 10].contains(signaturePitch);
  }

  NoteName spell(int pitch) {
    pitch %= 12;
    // Prefer the target scale's actual letter spelling (e.g. E# in F#).
    for (var degree = 0; degree < 7; degree++) {
      if ((tonic.pitch + intervals[degree]) % 12 == pitch) {
        final letter = NoteName
            .letters[(NoteName.letters.indexOf(tonic.letter) + degree) % 7];
        final natural = NoteName(letter, 0);
        return NoteName(letter, signedDistance(pitch - natural.pitch));
      }
    }
    final names = prefersFlats
        ? const [
            'C',
            'Db',
            'D',
            'Eb',
            'E',
            'F',
            'Gb',
            'G',
            'Ab',
            'A',
            'Bb',
            'B'
          ]
        : const [
            'C',
            'C#',
            'D',
            'D#',
            'E',
            'F',
            'F#',
            'G',
            'G#',
            'A',
            'A#',
            'B'
          ];
    return NoteName.tryParse(names[pitch])!;
  }

  /// Tonic-relative degrees; minor uses the natural minor scale.
  String degree(NoteName note) {
    final degree = (NoteName.letters.indexOf(note.letter) -
            NoteName.letters.indexOf(tonic.letter)) %
        7;
    final alteration =
        signedDistance(note.pitch - tonic.pitch - intervals[degree]);
    final prefix = alteration < 0 ? 'b' * -alteration : '#' * alteration;
    return '$prefix${degree + 1}';
  }
}

int signedDistance(int value) => (value + 6) % 12 - 6;

/// Supported chord suffixes are preserved literally, not reharmonized.
class ChordSymbol {
  const ChordSymbol(this.root, this.quality, [this.bass, this.rootDegree, this.bassDegree]);
  final NoteName root;
  final String quality;
  final NoteName? bass;
  /// Original relative spelling survives same-mode transposition.
  final String? rootDegree;
  final String? bassDegree;
  String get name =>
      '${root.name}$quality${bass == null ? '' : '/${bass!.name}'}';

  static ChordSymbol? tryParse(String token) {
    final rootMatch = RegExp(r'^([A-G][#b♯♭]{0,2})(.*)$').firstMatch(token);
    if (rootMatch == null) return null;
    var quality = rootMatch[2]!;
    NoteName? bass;
    final slash = RegExp(r'/([A-G][#b♯♭]{0,2})$').firstMatch(quality);
    if (slash != null) {
      bass = NoteName.tryParse(slash[1]!);
      quality = quality.substring(0, slash.start);
    }
    if (!RegExp(
            r'^(?:(?:maj|min|dim|aug|sus|add|omit|no|dom|alt)|[mMΔ+°ø0-9#b♯♭(),/\-])*$',
            caseSensitive: false)
        .hasMatch(quality)) {
      return null;
    }
    var depth = 0;
    for (final code in quality.codeUnits) {
      if (code == 40) depth++;
      if (code == 41) depth--;
      if (depth < 0) return null;
    }
    if (depth != 0 || quality.endsWith('/')) return null;
    return ChordSymbol(NoteName.tryParse(rootMatch[1]!)!, quality, bass);
  }

  /// Strict numbered roots/degrees; suffix vocabulary remains shared with
  /// letter chords. Numeric slash extensions are intentionally ambiguous.
  static ChordSymbol? tryParseNumbered(String token, MusicalKey key) {
    final match = RegExp(r'^([#b♯♭]{0,2}[1-7])(.*)$').firstMatch(token);
    if (match == null) return null;
    var suffix = match[2]!;
    String? bassDegree;
    final slash = RegExp(r'/([#b♯♭]{0,2}[1-7])$').firstMatch(suffix);
    if (slash != null) {
      bassDegree = slash[1]!;
      suffix = suffix.substring(0, slash.start);
    }
    if (suffix.contains('/') ||
        (suffix.isNotEmpty && RegExp(r'^\d').hasMatch(suffix) &&
            !RegExp(r'^(?:7|9|11|13)(?:$|[^0-9])').hasMatch(suffix))) {
      return null;
    }
    final parsed = tryParse('C$suffix');
    if (parsed == null) return null;
    NoteName resolve(String degree) {
      final index = int.parse(degree[degree.length - 1]) - 1;
      var alteration = 0;
      for (final code in degree.substring(0, degree.length - 1).runes) {
        alteration += code == 35 || code == 0x266f ? 1 : -1;
      }
      return key.spell(key.tonic.pitch + key.intervals[index] + alteration);
    }
    return ChordSymbol(resolve(match[1]!), suffix,
        bassDegree == null ? null : resolve(bassDegree), match[1], bassDegree);
  }

  ChordSymbol transpose(int semitones, MusicalKey spelling) => ChordSymbol(
      spelling.spell(root.pitch + semitones),
      quality,
      bass == null ? null : spelling.spell(bass!.pitch + semitones),
      rootDegree, bassDegree);

  String nashville(MusicalKey key) =>
      '${rootDegree ?? key.degree(root)}$quality${bass == null ? '' : '/${bassDegree ?? key.degree(bass!)}'}';
}
