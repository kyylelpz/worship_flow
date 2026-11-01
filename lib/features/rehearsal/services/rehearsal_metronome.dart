import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metronome/metronome_platform_interface.dart';

final rehearsalRouteObserverProvider =
    Provider((ref) => RouteObserver<PageRoute<dynamic>>());
final metronomeAudioProvider =
    Provider<MetronomeAudio>((ref) => NativeMetronomeAudio());

class MetronomePattern {
  const MetronomePattern(this.bpm, this.beats);
  final int bpm;
  final int beats;

  // One BPM pulse per quarter note in /4, per eighth note in /8.
  static MetronomePattern? parse(int? bpm, String? meter) {
    if (bpm == null || bpm < 1 || bpm > 400) return null;
    final beats = const {'3/4': 3, '4/4': 4, '6/8': 6, '8/8': 8}[meter?.trim()];
    return beats == null ? null : MetronomePattern(bpm, beats);
  }
}

abstract class MetronomeAudio {
  Future<void> prepare(MetronomePattern pattern);
  Future<void> play();
  Future<void> stop();
}

class NativeMetronomeAudio implements MetronomeAudio {
  bool _ready = false;
  MetronomePlatform get _platform => MetronomePlatform.instance;

  @override
  Future<void> prepare(MetronomePattern pattern) async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      throw UnsupportedError(
          'Metronome audio is unavailable on this platform.');
    }
    if (_ready) await stop();
    // Android/Windows consume raw PCM; AVAudioFile on Apple needs a WAV header.
    final extension = defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.windows
        ? 'pcm'
        : 'wav';
    // Await the platform initializer itself: the package facade does not await it.
    await _platform.init('assets/audio/tick.$extension',
        accentedPath: 'assets/audio/accent.$extension',
        bpm: pattern.bpm,
        timeSignature: pattern.beats,
        sampleRate: 44100,
        enableTickCallback: false);
    _ready = true;
  }

  @override
  Future<void> play() async {
    await _platform.play();
    if (await _platform.isPlaying() != true) {
      throw StateError('Audio playback could not start.');
    }
  }

  @override
  Future<void> stop() async {
    if (!_ready) return;
    // Pause before flushing so queued Android AudioTrack samples are discarded.
    await _platform.pause();
    await _platform.destroy();
    _ready = false;
  }
}

/// Serializes native operations; cancellation prevents late initialization from
/// starting playback. No Dart timers or widget-driven beat scheduling.
class RehearsalMetronome extends ValueNotifier<bool> {
  RehearsalMetronome(this.audio) : super(false);
  final MetronomeAudio audio;
  Future<void> _pending = Future.value();
  int _generation = 0;
  bool _disposed = false;

  Future<void> start(MetronomePattern pattern) {
    final generation = ++_generation;
    value = true;
    final result = _pending.then((_) async {
      if (_disposed || generation != _generation) return;
      await audio.stop();
      if (_disposed || generation != _generation) return;
      await audio.prepare(pattern);
      if (_disposed || generation != _generation) {
        await audio.stop();
        return;
      }
      await audio.play();
    });
    _pending = result.catchError((Object error, StackTrace stack) async {
      await audio.stop();
      if (!_disposed && generation == _generation) value = false;
    });
    return result;
  }

  void stop() {
    ++_generation;
    if (!_disposed) value = false;
    _pending = _pending
        .then((_) => audio.stop())
        .catchError((Object error, StackTrace stack) {
      debugPrint('Metronome stop failed: $error');
    });
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}
