import '../services/rehearsal_metronome.dart';
import '../../groups/providers/group_providers.dart';
import '../../../core/cache/cache_providers.dart';
import '../../../core/models/song.dart';
import 'package:flutter/material.dart';
import '../../../core/firebase/navigation_resume.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../songs/providers/song_providers.dart';
import '../../../core/models/setlist.dart';
import '../../../core/models/chart_settings.dart';
import '../../../core/models/setlist_item.dart';
import '../../../core/router/route_paths.dart';
import '../../auth/providers/auth_providers.dart';
import '../../charts/widgets/chord_chart_view.dart';
import '../../charts/data/chart_transformer.dart';
import '../../charts/models/chart_document.dart';
import '../../charts/providers/chart_providers.dart';
import '../../profile/screens/chart_settings_screen.dart';
import '../../setlists/providers/setlist_providers.dart';

class RehearsalScreen extends ConsumerWidget {
  const RehearsalScreen({super.key, required this.setlistId});
  final String setlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cacheChangesProvider);
    final cache = ref.watch(localContentCacheProvider);
    final group = ref.watch(selectedGroupIdProvider);
    // Keep the live subscriptions attached so reconnection refreshes the cache.
    ref.watch(groupSongsProvider);
    final setlist = ref.watch(setlistByIdProvider(setlistId));
    if (cache != null && group != null) {
      final cached = ref.watch(cachedRehearsalProvider((group, setlistId)));
      final offline = cache.isOffline(group);
      if (cached.asData != null) {
        final bundle = cached.asData!.value;
        return _RehearsalBody(
            key: ValueKey(bundle.setlist.id),
            setlist: bundle.setlist,
            cachedSongs: bundle.songs,
            offline: offline);
      }
      if (offline) {
        return cached.when(
            loading: () => Scaffold(
                appBar: AppBar(title: const Text('Rehearsal')),
                body: const Center(child: CircularProgressIndicator())),
            error: (error, _) => _Unavailable(
                message: error is StateError
                    ? 'Offline: ${error.message}'
                    : 'Offline charts are unavailable. Reconnect and refresh to cache them again.',
                onRetry: () {
                  ref.invalidate(groupSetlistsProvider);
                  ref.invalidate(groupSongsProvider);
                  ref.invalidate(allGroupsProvider);
                  ref.invalidate(userGroupsProvider);
                  ref.invalidate(cachedRehearsalProvider((group, setlistId)));
                }),
            data: (_) => const SizedBox.shrink());
      }
    }
    return setlist.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Rehearsal')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _Unavailable(
        message: 'Could not load setlist.',
        onRetry: () {
          ref.invalidate(groupSetlistsProvider);
          ref.invalidate(setlistByIdProvider(setlistId));
        },
      ),
      data: (value) => value == null
          ? const _Unavailable(message: 'Setlist not found.')
          : _RehearsalBody(key: ValueKey(value.id), setlist: value),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rehearsal')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              TextButton(
                onPressed: () => context.go(RoutePaths.setlists),
                child: const Text('Back to Setlists'),
              ),
            ],
          ),
        ),
      );
}

class _RehearsalBody extends ConsumerStatefulWidget {
  const _RehearsalBody(
      {super.key,
      required this.setlist,
      this.cachedSongs,
      this.offline = false});
  final List<Song>? cachedSongs;
  final bool offline;
  final Setlist setlist;

  @override
  ConsumerState<_RehearsalBody> createState() => _RehearsalBodyState();
}

class _RehearsalBodyState extends ConsumerState<_RehearsalBody>
    with RouteAware, WidgetsBindingObserver {
  late final RehearsalMetronome _metronome;
  late final RouteObserver<PageRoute<dynamic>> _routeObserver;
  PageRoute<dynamic>? _route;
  String? _metronomeSong;

  @override
  void initState() {
    super.initState();
    _metronome = RehearsalMetronome(ref.read(metronomeAudioProvider));
    _routeObserver = ref.read(rehearsalRouteObserverProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      _routeObserver.unsubscribe(this);
      _route = route;
      _routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => _metronome.stop();

  @override
  void didPop() => _metronome.stop();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _metronome.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routeObserver.unsubscribe(this);
    _metronome.dispose();
    super.dispose();
  }

  int _selected = 0;
  double _drag = 0;
  bool _showSections = true;
  bool _previewDraft = false;
  bool _resumeSelected = false;
  String? _lastRecorded;

  @override
  void didUpdateWidget(_RehearsalBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the selected occurrence across reorder/save, including duplicates.
    final oldItems = _items(oldWidget.setlist);
    final newItems = _items(widget.setlist);
    if (_selected < oldItems.length) {
      final selected = oldItems[_selected];
      final occurrence = oldItems
          .take(_selected + 1)
          .where((item) => item.songId == selected.songId)
          .length;
      var seen = 0;
      final index = newItems.indexWhere(
          (item) => item.songId == selected.songId && ++seen == occurrence);
      _selected = index < 0 ? 0 : index;
    } else {
      _selected = 0;
    }
  }

  List<SetlistItem> _items(Setlist setlist) {
    final canEdit = !widget.offline &&
        (ref.read(currentRoleProvider)?.canManageSetlists ?? false);
    if (setlist.isPublished && (!_previewDraft || !canEdit)) {
      return setlist.publishedItems;
    }
    return canEdit ? setlist.draftItems ?? setlist.publishedItems : const [];
  }

  Future<void> _openManagement(String destination) async {
    Navigator.of(context).pop(); // Close drawer before pushing the editor.
    await context.push(destination);
    if (!mounted) return;
    ref.invalidate(setlistByIdProvider(widget.setlist.id));
  }

  @override
  Widget build(BuildContext context) {
    final setlist = widget.setlist;
    final role = ref.watch(currentRoleProvider);
    final canEdit = !widget.offline && (role?.canManageSetlists ?? false);
    final items = _items(setlist);
    final availableSongs =
        widget.cachedSongs ?? ref.watch(groupSongsProvider).asData?.value;
    if (!_resumeSelected && items.isNotEmpty && availableSongs != null) {
      _resumeSelected = true;
      final resume = ref.read(sessionResumeProvider).valueOrNull?.location;
      if (resume?.setlistId == setlist.id &&
          resume?.groupId == setlist.groupId) {
        final found = items.indexWhere((i) =>
            i.songId == resume?.songId &&
            availableSongs.any((s) => s.id == i.songId));
        final first = items
            .indexWhere((i) => availableSongs.any((s) => s.id == i.songId));
        _selected = found < 0 ? (first < 0 ? 0 : first) : found;
      }
    }
    final index = _selected < items.length ? _selected : 0;
    final item = items.isEmpty ? null : items[index];
    final record = '${setlist.id}|${item?.songId}';
    if (_lastRecorded != record && availableSongs != null) {
      _lastRecorded = record;
      final uid = ref.read(currentUserProvider)?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(currentUserProvider)?.id == uid &&
            ref.read(selectedGroupIdProvider) == setlist.groupId) {
          rememberLocation(
              ref,
              ResumeLocation(
                  groupId: setlist.groupId,
                  setlistId: setlist.id,
                  songId: item?.songId));
        }
      });
    }
    final AsyncValue<List<Song>> asyncSongs = widget.cachedSongs == null
        ? ref.watch(groupSongsProvider)
        : AsyncData(widget.cachedSongs!);
    if (asyncSongs.isLoading) {
      return Scaffold(
          appBar: AppBar(title: const Text('Rehearsal')),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (asyncSongs.hasError) {
      return Scaffold(
          appBar: AppBar(title: const Text('Rehearsal')),
          body:
              Center(child: Text('Could not load songs: ${asyncSongs.error}')));
    }
    final List<Song> songs =
        widget.cachedSongs ?? ref.watch<List<Song>>(songsListProvider);
    final song = songs.where((song) => song.id == item?.songId).firstOrNull;
    final arrangement = song?.arrangements
        .where((arrangement) => arrangement.id == item?.arrangementId)
        .firstOrNull;
    final metronomeSong =
        '${item?.songId}/${item?.arrangementId}/$index/${arrangement?.bpm}/${arrangement?.timeSignature}';
    if (_metronomeSong != metronomeSong) {
      _metronome.stop();
      _metronomeSong = metronomeSong;
    }
    final settings = ref.watch(chartSettingsProvider);

    final personal =
        ref.watch(personalTransposeProvider(arrangement?.id ?? ''));
    DisplayChart? chart;
    String? chartError;
    if (song != null && arrangement != null) {
      try {
        chart = const ChartTransformer().prepare(
            song: song,
            arrangement: arrangement,
            item: item,
            settings: settings,
            personalSemitones: personal);
      } on ArgumentError catch (error) {
        chartError = 'Chart unavailable: ${error.message}';
      }
    }
    final settingsController = ref.read(chartSettingsProvider.notifier);

    void select(int next) {
      if (next >= 0 && next < items.length && next != index) {
        _metronome.stop();
        setState(() => _selected = next);
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Open setlist',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(78),
        title: Semantics(
            button: !widget.offline &&
                ref.watch(canManageSongsProvider) &&
                song != null,
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.offline ||
                        !ref.watch(canManageSongsProvider) ||
                        song == null ||
                        arrangement == null ||
                        item == null
                    ? null
                    : () async {
                        final action = await showDialog<String>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                                    title: Text(song.title),
                                    content: Text(
                                        'Artist: ${song.artist}\nArrangement: ${arrangement.name}\n'
                                        'Worship Leader: ${item.vocalistName ?? "Not selected"}\nKey: ${item.performanceKey}'
                                        '${personal == 0 ? "" : "\nDisplayed key: ${chart?.document.key?.name ?? item.performanceKey}"}'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, 'song'),
                                          child: const Text('Edit Song')),
                                      if (canEdit)
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, 'setlist'),
                                            child: const Text('Edit Setlist'))
                                    ]));
                        if (!context.mounted || action == null) return;
                        await context.push(action == 'song'
                            ? RoutePaths.songEditorFor(song.id)
                            : RoutePaths.setlistEditorFor(setlist.id));
                        if (mounted && action == 'setlist') {
                          ref.invalidate(setlistByIdProvider(setlist.id));
                        }
                      },
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song?.title ?? 'Rehearsal',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (song != null)
                        Text(song.artist,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      Text(
                          item == null
                              ? setlist.name
                              : 'Key of ${item.performanceKey} · ${arrangement?.timeSignature ?? "—"}'
                                  '${personal == 0 ? "" : " · Display ${chart?.document.key?.name ?? item.performanceKey}"}',
                          style: Theme.of(context).textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ]))),
        actions: [
          IconButton(
            tooltip: 'Chart controls',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => context.push(RoutePaths.chartSettings),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _metronome,
            builder: (context, playing, _) => Semantics(
              toggled: playing,
              child: IconButton(
                tooltip: playing ? 'Stop metronome' : 'Start metronome',
                color: playing
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                icon: const Icon(Icons.av_timer_rounded),
                onPressed: () async {
                  if (playing) {
                    _metronome.stop();
                    return;
                  }
                  final pattern = MetronomePattern.parse(
                      arrangement?.bpm, arrangement?.timeSignature);
                  if (pattern == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Metronome needs a BPM from 1–400 and 3/4, 4/4, 6/8 or 8/8 time.')));
                    return;
                  }
                  try {
                    await _metronome.start(pattern);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text('Metronome audio unavailable. Try again.')));
                    }
                  }
                },
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: const Text('Back to Setlists'),
                onTap: () {
                  _metronome.stop();
                  context.go(RoutePaths.setlists);
                },
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(setlist.name,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(DateFormat('EEE, MMM d · h:mm a')
                        .format(setlist.serviceDateTime)),
                    Text(setlist.isPublished
                        ? setlist.hasDraftChanges
                            ? 'Published · Unpublished changes'
                            : 'Published'
                        : canEdit
                            ? 'Draft · Preview'
                            : 'Draft'),
                  ],
                ),
              ),
              if (canEdit)
                TextButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openManagement(
                        RoutePaths.setlistEditorFor(setlist.id)),
                    label: const Text('Edit Setlist')),
              if (canEdit && setlist.isPublished && setlist.hasDraftChanges)
                TextButton.icon(
                    icon: const Icon(Icons.preview_outlined),
                    label: Text(_previewDraft
                        ? 'View Published Setlist'
                        : 'Preview Draft'),
                    onPressed: () {
                      _metronome.stop();
                      setState(() {
                        _previewDraft = !_previewDraft;
                        _selected = 0;
                      });
                      Navigator.of(context).pop();
                    }),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    if (items.isEmpty)
                      const ListTile(title: Text('No songs available.')),
                    for (var i = 0; i < items.length; i++)
                      ListTile(
                        key: ValueKey('setlist-song-$i'),
                        selected: i == index,
                        selectedTileColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        leading: Text('${i + 1}'),
                        title: Text(songs
                                .where((song) => song.id == items[i].songId)
                                .firstOrNull
                                ?.title ??
                            'Unavailable song'),
                        trailing: Text(items[i].performanceKey),
                        onTap: () {
                          select(i);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (widget.offline)
            MaterialBanner(
                content: const Text('Offline · Cached charts · Read only'),
                leading: const Icon(Icons.cloud_off_outlined),
                actions: [
                  TextButton(
                      onPressed: () {
                        ref.invalidate(groupSetlistsProvider);
                        ref.invalidate(groupSongsProvider);
                      },
                      child: const Text('Refresh'))
                ]),
          if (_previewDraft && canEdit)
            const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Draft preview · unpublished changes')),
          if (arrangement != null)
            SafeArea(
              top: false,
              bottom: false,
              child: Row(children: [
                Expanded(
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          const SizedBox(width: 8),
                          DropdownButton<ChartDisplayMode>(
                            value: settings.displayMode,
                            hint: const Text('Display mode'),
                            items: [
                              for (final mode in ChartDisplayMode.values)
                                DropdownMenuItem(
                                    value: mode, child: Text(mode.label))
                            ],
                            onChanged: (mode) {
                              if (mode != null) {
                                settingsController.update(
                                    (s) => s.copyWith(displayMode: mode));
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                              tooltip: 'Transpose down',
                              icon: const Icon(Icons.remove),
                              onPressed: personal > -12
                                  ? () => ref
                                      .read(personalTransposeProvider(
                                              arrangement.id)
                                          .notifier)
                                      .state--
                                  : null),
                          Text('$personal'),
                          IconButton(
                              tooltip: 'Transpose up',
                              icon: const Icon(Icons.add),
                              onPressed: personal < 12
                                  ? () => ref
                                      .read(personalTransposeProvider(
                                              arrangement.id)
                                          .notifier)
                                      .state++
                                  : null),
                        ]))),
                IconButton(
                    tooltip: 'Smaller chart text',
                    icon: const Icon(Icons.text_decrease),
                    onPressed: () {
                      settingsController.adjustLyrics(-1);
                      settingsController.adjustChords(-1);
                    }),
                IconButton(
                    tooltip: 'Larger chart text',
                    icon: const Icon(Icons.text_increase),
                    onPressed: () {
                      settingsController.adjustLyrics(1);
                      settingsController.adjustChords(1);
                    }),
                IconButton(
                  tooltip: _showSections ? 'Hide Sections' : 'Show Sections',
                  isSelected: _showSections,
                  icon: const Icon(Icons.segment),
                  onPressed: () =>
                      setState(() => _showSections = !_showSections),
                ),
              ]),
            ),
          if (!setlist.isPublished)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(canEdit
                  ? 'Draft preview · not published'
                  : 'This setlist has not been published.'),
            ),
          Expanded(
            child: item == null
                ? Center(
                    child: Text(setlist.isPublished || canEdit
                        ? 'No songs in this setlist. Open the setlist menu to manage it.'
                        : 'No published songs available.'))
                : GestureDetector(
                    key: const ValueKey('song-swipe'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _drag = 0,
                    onHorizontalDragUpdate: (details) =>
                        _drag += details.delta.dx,
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (_drag.abs() > 60 || velocity.abs() > 300) {
                        final direction =
                            velocity.abs() > 300 ? velocity : _drag;
                        select(index + (direction < 0 ? 1 : -1));
                      }
                    },
                    child: arrangement == null
                        ? const Center(
                            child: Text(
                                'Song or arrangement unavailable. Choose another song from the setlist.'))
                        : chart == null
                            ? Center(
                                child: Text(chartError ?? 'Chart unavailable.'))
                            : ChordChartView(
                                key: ValueKey(
                                    '$index-${item.songId}-${item.arrangementId}'),
                                showSections: _showSections,
                                chart: chart,
                                settings: settings,
                              ),
                  ),
          ),
        ],
      ),
    );
  }
}
