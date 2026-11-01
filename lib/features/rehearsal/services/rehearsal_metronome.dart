import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const _androidChannel = MethodChannel('metronome');
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<T?> _androidCall<T>(String method,
          [Map<String, dynamic>? arguments]) =>
      _androidChannel.invokeMethod<T>(method, arguments).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
              'Android metronome $method did not reply. Fully rebuild the app.'));
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
    if (_android) {
      final normal = await rootBundle.load('assets/audio/tick.pcm');
      final accent = await rootBundle.load('assets/audio/accent.pcm');
      // Use the same plugin channel directly so native errors are not swallowed
      // by the package's Dart wrapper. MainActivity supplies missing void replies.
      _ready = true; // Clean up even if native initialization times out/fails.
      await _androidCall<void>('init', {
        'mainFileBytes': normal.buffer
            .asUint8List(normal.offsetInBytes, normal.lengthInBytes),
        'accentedFileBytes': accent.buffer
            .asUint8List(accent.offsetInBytes, accent.lengthInBytes),
        'bpm': pattern.bpm,
        'timeSignature': pattern.beats,
        'sampleRate': 44100,
        'volume': 0.75,
        'enableTickCallback': false,
      });
    } else {
      await _platform.init('assets/audio/tick.$extension',
          accentedPath: 'assets/audio/accent.$extension',
          bpm: pattern.bpm,
          timeSignature: pattern.beats,
          sampleRate: 44100,
          enableTickCallback: false);
    }
    _ready = true;
  }

  @override
  Future<void> play() async {
    if (_android) {
      await _androidCall<void>('play');
    } else {
      await _platform.play();
    }
    final playing = _android
        ? await _androidCall<bool>('isPlaying')
        : await _platform.isPlaying();
    if (playing != true) {
      throw StateError('Audio playback could not start.');
    }
  }

  @override
  Future<void> stop() async {
    if (!_ready) return;
    // Pause before flushing so queued Android AudioTrack samples are discarded.
    try {
      if (_android) {
        await _androidCall<void>('pause');
      } else {
        await _platform.pause();
      }
    } finally {
      try {
        if (_android) {
          await _androidCall<void>('destroy');
        } else {
          await _platform.destroy();
        }
      } finally {
        _ready = false;
      }
    }
  }
}

/// Serializes native operations; cancellation prevents late initialization from
/// starting playback. No Dart timers or widget-driven beat scheduling.
class RehearsalMetronome extends ValueNotifier<bool> {
  RehearsalMetronome(this.audio) : super(false);
  final MetronomeAudio audio;
  // Routes can overlap while native initialization is pending. The shared audio
  // engine needs one operation queue across both departing and arriving views.
  static final _queues = Expando<_AudioOperations>();
  late final _operations = _queues[audio] ??= _AudioOperations();
  Future<void> get _pending => _operations.pending;
  set _pending(Future<void> value) => _operations.pending = value;
  int _generation = 0;
  bool _disposed = false;

  Future<void> start(MetronomePattern pattern) {
    if (_operations.owner != this) _operations.owner?.stop();
    _operations.owner = this;
    final generation = ++_generation;
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
      if (!_disposed && generation == _generation) {
        value = true;
      } else {
        await audio.stop();
      }
    });
    _pending = result.catchError((Object error, StackTrace stack) async {
      if (!_disposed && generation == _generation) value = false;
      if (kDebugMode) debugPrint('[Metronome] start failed: $error\n$stack');
      try {
        await audio.stop();
      } catch (cleanupError) {
        if (kDebugMode) debugPrint('[Metronome] cleanup failed: $cleanupError');
      }
    });
    return result;
  }

  void stop() {
    ++_generation;
    if (!_disposed) value = false;
    // Disposal of an old route may finish after the new route has started.
    if (_operations.owner != this) return;
    _operations.owner = null;
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

class _AudioOperations {
  Future<void> pending = Future.value();
  RehearsalMetronome? owner;
}
