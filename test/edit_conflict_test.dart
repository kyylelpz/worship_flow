import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/edit_conflict.dart';
import 'package:worship_flow/features/songs/widgets/chordpro_source_field.dart';
import 'package:worship_flow/features/songs/providers/song_providers.dart';
import 'package:worship_flow/features/songs/screens/arrangement_editor_screen.dart';
import 'firestore_phase3c_test.dart' as setlists;
import 'song_management_test.dart' as songs;
import 'song_repository_test.dart' as data;

void main() {
  for (final choice in ['Keep Editing', 'Cancel', 'Reload Latest']) {
    testWidgets(
        'stale Setlist: $choice preserves remote and handles local draft',
        (t) async {
      final (_, repo, _) =
          await setlists.launch(t, route: '/setlists/setlist-1/edit');
      final original = (await t.runAsync(() => repo.getSetlist('setlist-1')))!;
      await t.enterText(find.byType(TextField).first, 'Local unsaved');
      await t.runAsync(() => repo.commitSetlist(
          id: original.id,
          groupId: original.groupId,
          name: 'Remote latest',
          serviceDateTime: original.serviceDateTime,
          items: original.publishedItems,
          expectedRevision: original.revision));
      await t.pump();
      await t.tap(find.text('Save Draft'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Setlist changed'), findsOneWidget);
      await t.tap(find.text(choice));
      await t.pumpAndSettle();
      expect(
          find.text(
              choice == 'Reload Latest' ? 'Remote latest' : 'Local unsaved'),
          findsOneWidget);
      expect((await t.runAsync(() => repo.getSetlist(original.id)))!.name,
          'Remote latest');
      expect(
          (await t.runAsync(() => repo.getSetlist(original.id)))!
              .publishedItems,
          original.publishedItems);
      if (choice == 'Reload Latest') {
        await t.enterText(find.byType(TextField).first, 'Reconciled');
        await t.pump();
        await t.tap(find.text('Save Draft'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect((await t.runAsync(() => repo.getSetlist(original.id)))!.name,
            'Reconciled');
      } else {
        await setlists.back(t);
        expect(find.text('Save Setlist as Draft?'), findsOneWidget);
      }
    });
  }
  testWidgets('deleted Setlist cannot be recreated by repeated stale saves',
      (t) async {
    final (_, repo, _) =
        await setlists.launch(t, route: '/setlists/setlist-1/edit');
    await t.enterText(find.byType(TextField).first, 'Deleted local draft');
    await t.runAsync(() => repo.delete('setlist-1'));
    for (var attempt = 0; attempt < 2; attempt++) {
      await t.pump();
      await t.tap(find.text('Save Draft'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Setlist deleted'), findsOneWidget);
      await t.tap(find.text('Keep Editing'));
      await t.pumpAndSettle();
      expect(find.text('Deleted local draft'), findsOneWidget);
      expect(await t.runAsync(() => repo.getSetlist('setlist-1')), isNull);
    }
  });
  test(
      'Song/Arrangement baseline comparisons reject concurrent and deleted edits',
      () async {
    final f = data.CatalogFixture();
    addTearDown(f.dispose);
    final id = await f.repo.createSong('group-1', data.draftSong());
    final original = (await f.repo.getSong('group-1', id))!;
    await f.repo.updateSong('group-1', original.copyWith(title: 'Remote'),
        expected: original);
    await expectLater(
        f.repo.updateSong('group-1', original.copyWith(title: 'Stale'),
            expected: original),
        throwsA(isA<EditConflict>()));
    final arrangement = original.primaryArrangement;
    await f.repo.updateArrangement(
        'group-1', id, arrangement.copyWith(chordProSource: 'Remote source'),
        expected: arrangement);
    await expectLater(
        f.repo.updateArrangement(
            'group-1', id, arrangement.copyWith(chordProSource: 'Stale source'),
            expected: arrangement),
        throwsA(isA<EditConflict>()));
    expect(
        (await f.repo.getSong('group-1', id))!
            .primaryArrangement
            .chordProSource,
        'Remote source');
    await f.repo.deleteSong('group-1', id);
    await expectLater(
        f.repo.updateSong('group-1', original, expected: original),
        throwsA(isA<EditConflict>().having((e) => e.deleted, 'deleted', true)));
    await expectLater(
        f.repo.updateArrangement('group-1', id, arrangement,
            expected: arrangement),
        throwsA(isA<EditConflict>().having((e) => e.deleted, 'deleted', true)));
    expect(await f.repo.getSong('group-1', id), isNull);
  });
  testWidgets('Song metadata conflict retains fields until explicit reload',
      (t) async {
    final c = await songs.launch(t, route: '/songs/song-1/edit');
    final original = c.read(songByIdProvider('song-1'))!;
    await songs.enter(t, 'Title', 'Unsaved title');
    await t.runAsync(() => c
        .read(songRepositoryProvider)
        .updateSong('group-1', original.copyWith(title: 'Remote title')));
    await t.pumpAndSettle();
    await t.tap(find.text('Save Song'));
    await t.pumpAndSettle();
    expect(find.text('Song changed'), findsOneWidget);
    await t.tap(find.text('Keep Editing'));
    await t.pumpAndSettle();
    expect(find.text('Unsaved title'), findsOneWidget);
    await t.tap(find.text('Save Song'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reload Latest'));
    await t.pumpAndSettle();
    expect(find.text('Remote title'), findsOneWidget);
  });
  testWidgets(
      'Arrangement conflict keeps editor and exact local source; reload is explicit',
      (t) async {
    final c = await songs.launch(t, route: '/songs/song-1/edit');
    final original = c.read(songByIdProvider('song-1'))!.primaryArrangement;
    await t.ensureVisible(find.text('Full Band'));
    await t.tap(find.text('Full Band'));
    await t.pumpAndSettle();
    await songs.enter(t, 'Arrangement name', 'Local Band');
    final localSource = '${original.chordProSource}\n[1] Local draft  ';
    t
        .widget<ChordProSourceField>(find.byType(ChordProSourceField))
        .controller
        .text = localSource;
    await t.runAsync(() => c.read(songRepositoryProvider).updateArrangement(
        'group-1', 'song-1', original.copyWith(name: 'Remote Band')));
    await t.pumpAndSettle();
    await t.tap(find.text('Save Arrangement'));
    await t.pumpAndSettle();
    expect(find.text('Arrangement changed'), findsOneWidget);
    await t.tap(find.text('Keep Editing'));
    await t.pumpAndSettle();
    expect(find.byType(ArrangementEditorScreen), findsOneWidget);
    expect(find.text('Local Band'), findsOneWidget);
    expect(
        t
            .widget<ChordProSourceField>(find.byType(ChordProSourceField))
            .controller
            .text,
        localSource);
    await t.tap(find.text('Save Arrangement'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reload Latest'));
    await t.pumpAndSettle();
    expect(find.text('Remote Band'), findsOneWidget);
    expect(
        c.read(songByIdProvider('song-1'))!.primaryArrangement.chordProSource,
        original.chordProSource);
  });
  test(
      'independent metadata and arrangement edits merge; simultaneous metadata saves conflict',
      () async {
    final f = data.CatalogFixture();
    addTearDown(f.dispose);
    final original = (await f.repo.getSong('group-1', 'song-1'))!;
    final arrangement = original.primaryArrangement;
    await f.repo.updateArrangement(
        'group-1', original.id, arrangement.copyWith(bpm: 101),
        expected: arrangement);
    await f.repo.updateSong(
        'group-1', original.copyWith(title: 'Metadata only'),
        expected: original);
    final latest = (await f.repo.getSong('group-1', original.id))!;
    expect(latest.primaryArrangement.bpm, 101);
    final outcomes = await Future.wait([
      for (final title in ['Editor A', 'Editor B'])
        f.repo
            .updateSong('group-1', latest.copyWith(title: title),
                expected: latest)
            .then<Object?>((_) => null, onError: (Object error) => error),
    ]);
    expect(outcomes.whereType<EditConflict>(), hasLength(1));
    expect(outcomes.where((v) => v == null), hasLength(1));
  });
  testWidgets('deleted Song keeps metadata draft and never becomes a create',
      (t) async {
    final c = await songs.launch(t, route: '/songs/song-1/edit');
    final repo = c.read(songRepositoryProvider);
    final id =
        await t.runAsync(() => repo.createSong('group-1', data.draftSong()));
    // The fixture song is referenced, so use a fresh unreferenced record.
    c.read(routing.appRouterProvider).go('/songs/$id/edit');
    await t.pumpAndSettle();
    await songs.enter(t, 'Title', 'Deleted draft');
    await t.runAsync(() => repo.deleteSong('group-1', id!));
    await t.pumpAndSettle();
    await t.tap(find.text('Save Song'));
    await t.pumpAndSettle();
    expect(find.text('Song deleted'), findsOneWidget);
    await t.tap(find.text('Keep Editing'));
    await t.pumpAndSettle();
    expect(find.text('Deleted draft'), findsOneWidget);
    expect(await t.runAsync(() => repo.getSong('group-1', id!)), isNull);
  });
}
