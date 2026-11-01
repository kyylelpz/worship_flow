import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/firebase/firebase_providers.dart';
import 'package:worship_flow/core/mock_data/mock_users.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/core/router/route_paths.dart';
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/rehearsal/services/rehearsal_metronome.dart';
import 'package:worship_flow/features/setlists/data/mock_setlist_repository.dart';
import 'package:worship_flow/features/setlists/providers/setlist_providers.dart';
import 'package:worship_flow/features/songs/providers/song_providers.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/models/song.dart';

class FakeAudio implements MetronomeAudio {
  final patterns = <MetronomePattern>[];
  int playing = 0;
  int starts = 0;
  Completer<void>? preparation;
  @override
  Future<void> prepare(MetronomePattern pattern) async {
    patterns.add(pattern);
    await preparation?.future;
  }

  @override
  Future<void> play() async {
    playing++;
    starts++;
  }

  @override
  Future<void> stop() async {
    playing = 0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'native audio receives bundled distinct ticks and bar lengths; pause precedes release',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('metronome_tick'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('metronome'),
        (call) async {
      calls.add(call);
      return call.method == 'isPlaying' ? true : null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('metronome'), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('metronome_tick'), null);
    });
    final audio = NativeMetronomeAudio();
    for (final beats in [3, 4, 6, 8]) {
      await audio.prepare(MetronomePattern(97, beats));
      await audio.play();
      await audio.stop();
      final config =
          calls.lastWhere((c) => c.method == 'init').arguments as Map;
      expect(config['bpm'], 97);
      expect(config['timeSignature'], beats);
      expect(config['enableTickCallback'], false);
      expect(config['sampleRate'], 44100);
      expect(config['mainFileBytes'], isNotEmpty);
      expect(
          config['accentedFileBytes'], isNot(equals(config['mainFileBytes'])));
      expect(calls.sublist(calls.length - 2).map((c) => c.method),
          ['pause', 'destroy']);
    }
  });
  test('validates exact meters and forwards BPM without compound grouping',
      () async {
    final audio = FakeAudio();
    final player = RehearsalMetronome(audio);
    for (final meter in ['3/4', '4/4', '6/8', '8/8']) {
      await player.start(MetronomePattern.parse(123, meter)!);
      player.stop();
      await Future<void>.delayed(Duration.zero);
    }
    expect(audio.patterns.map((p) => p.beats), [3, 4, 6, 8]);
    expect(audio.patterns.map((p) => p.bpm), everyElement(123));
    for (final bpm in [null, 0, -1, 401]) {
      expect(MetronomePattern.parse(bpm, '4/4'), isNull);
    }
    expect(MetronomePattern.parse(120, '5/4'), isNull);
    expect(MetronomePattern.parse(120, null), isNull);
    player.dispose();
  });

  test('stop/dispose cancel pending starts; repeated starts never overlap',
      () async {
    final audio = FakeAudio()..preparation = Completer<void>();
    final player = RehearsalMetronome(audio);
    final start = player.start(const MetronomePattern(100, 4));
    await Future<void>.delayed(Duration.zero);
    player.stop();
    audio.preparation!.complete();
    await start;
    await Future<void>.delayed(Duration.zero);
    expect(audio.starts, 0);
    expect(player.value, false);
    audio.preparation = null;
    await player.start(const MetronomePattern(80, 3));
    final first = player.start(const MetronomePattern(120, 6));
    final last = player.start(const MetronomePattern(140, 8));
    await Future.wait([first, last]);
    expect(audio.playing, 1);
    expect(audio.patterns.last.beats, 8);
    player.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(audio.playing, 0);
  });

  testWidgets('button toggles, stops on song switch and pushed settings',
      (tester) async {
    final audio = FakeAudio();
    final songs = StreamController<List<Song>>();
    final repository = MockSetlistRepository(delay: Duration.zero);
    final container = ProviderContainer(overrides: [
      useMockBackendProvider.overrideWithValue(true),
      metronomeAudioProvider.overrideWithValue(audio),
      setlistRepositoryProvider.overrideWithValue(repository),
      groupSongsProvider.overrideWith((ref) async* {
        yield mockSongs;
        yield* songs.stream;
      }),
    ]);
    final auth = container.read(sessionProvider.notifier);
    auth.updateProfile(mockCurrentUser);
    auth.selectGroup('group-1');
    final router = container.read(routing.appRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    router.go('/setlists/setlist-1/rehearse');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Start metronome'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Stop metronome'), findsOneWidget);
    expect(audio.playing, 1);
    final button = tester.widget<IconButton>(find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Stop metronome'));
    final context = tester.element(find.byTooltip('Stop metronome'));
    expect(button.color, Theme.of(context).colorScheme.primary);
    await tester.tap(find.byTooltip('Stop metronome'));
    await tester.pumpAndSettle();
    expect(audio.playing, 0);
    await tester.tap(find.byTooltip('Start metronome'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open setlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setlist-song-1')));
    await tester.pumpAndSettle();
    expect(audio.playing, 0);
    expect(find.byTooltip('Start metronome'), findsOneWidget);
    await tester.tap(find.byTooltip('Start metronome'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chart controls'));
    await tester.pumpAndSettle();
    expect(audio.playing, 0);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start metronome'), findsOneWidget);
    await tester.tap(find.byTooltip('Start metronome'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(audio.playing, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start metronome'), findsOneWidget);
    await tester.tap(find.byTooltip('Start metronome'));
    await tester.pumpAndSettle();
    router.go(RoutePaths.setlists);
    await tester.pumpAndSettle();
    expect(audio.playing, 0);
    router.go('/setlists/setlist-1/rehearse');
    await tester.pumpAndSettle();
    songs.add([
      for (final song in mockSongs)
        song.copyWith(arrangements: [
          for (final arrangement in song.arrangements)
            arrangement.copyWith(bpm: 0),
        ])
    ]);
    await tester.pumpAndSettle();
    final starts = audio.starts;
    await tester.tap(find.byTooltip('Start metronome'));
    await tester.pumpAndSettle();
    expect(audio.starts, starts);
    expect(find.textContaining('Metronome needs a BPM'), findsOneWidget);
    expect(find.byTooltip('Start metronome'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    container.dispose();
    repository.dispose();
    unawaited(songs.close());
  });
}
