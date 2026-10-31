import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/mock_data/mock_songs.dart';
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
    final setlist = ref.watch(setlistByIdProvider(setlistId));
    return setlist.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Rehearsal')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _Unavailable(
        message: 'Could not load setlist.',
        onRetry: () => ref.invalidate(setlistByIdProvider(setlistId)),
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
  const _RehearsalBody({super.key, required this.setlist});
  final Setlist setlist;

  @override
  ConsumerState<_RehearsalBody> createState() => _RehearsalBodyState();
}

class _RehearsalBodyState extends ConsumerState<_RehearsalBody> {
  int _selected = 0;
  double _drag = 0;

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
    if (setlist.isPublished) return setlist.publishedItems;
    final canEdit = ref.read(currentRoleProvider)?.canManageSetlists ?? false;
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
    final canEdit = role?.canManageSetlists ?? false;
    final items = _items(setlist);
    final index = _selected < items.length ? _selected : 0;
    final item = items.isEmpty ? null : items[index];
    final song = mockSongs.where((song) => song.id == item?.songId).firstOrNull;
    final arrangement = song?.arrangements
        .where((arrangement) => arrangement.id == item?.arrangementId)
        .firstOrNull;
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(song?.title ?? 'Rehearsal',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              item == null
                  ? setlist.name
                  : 'Key ${chart?.document.key?.name ?? item.performanceKey} · ${index + 1}/${items.length}',
              style: Theme.of(context).textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chart controls',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => context.push(RoutePaths.chartSettings),
          ),
          IconButton(
            tooltip: 'Live Mode',
            icon: const Icon(Icons.play_circle_outline_rounded),
            onPressed: item != null &&
                    setlist.isPublished &&
                    (role?.canEnterLiveMode ?? false)
                ? () => context.push(RoutePaths.setlistLiveFor(setlist.id))
                : null,
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
                onTap: () => context.go(RoutePaths.setlists),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                        onPressed: () => _openManagement(
                            RoutePaths.setlistEditorFor(setlist.id)),
                        child: const Text('Edit')),
                    TextButton(
                        onPressed: () => _openManagement(
                            RoutePaths.setlistEditorFor(setlist.id)),
                        child: const Text('Reorder')),
                  ],
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title:
                    Text(canEdit ? 'Details & management' : 'Setlist details'),
                onTap: () =>
                    _openManagement(RoutePaths.setlistDetailsFor(setlist.id)),
              ),
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
                        title: Text(mockSongs
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
          if (arrangement != null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                const SizedBox(width: 8),
                DropdownButton<ChartDisplayMode>(
                  value: settings.displayMode,
                  hint: const Text('Display mode'),
                  items: [
                    for (final mode in ChartDisplayMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label))
                  ],
                  onChanged: (mode) {
                    if (mode != null) {
                      settingsController
                          .update((s) => s.copyWith(displayMode: mode));
                    }
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                    tooltip: 'Transpose down',
                    icon: const Icon(Icons.remove),
                    onPressed: personal > -12
                        ? () => ref
                            .read(personalTransposeProvider(arrangement.id)
                                .notifier)
                            .state--
                        : null),
                Text('$personal'),
                IconButton(
                    tooltip: 'Transpose up',
                    icon: const Icon(Icons.add),
                    onPressed: personal < 12
                        ? () => ref
                            .read(personalTransposeProvider(arrangement.id)
                                .notifier)
                            .state++
                        : null),
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
