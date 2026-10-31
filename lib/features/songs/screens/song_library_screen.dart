import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/song_providers.dart';
import '../../../core/models/song.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';

final _songSearchProvider = StateProvider<String>((ref) => '');
final _songCategoryProvider = StateProvider<String?>((ref) => null);

class SongLibraryScreen extends ConsumerStatefulWidget {
  const SongLibraryScreen({super.key});

  @override
  ConsumerState<SongLibraryScreen> createState() => _SongLibraryScreenState();
}

class _SongLibraryScreenState extends ConsumerState<SongLibraryScreen> {
  late final _searchController =
      TextEditingController(text: ref.read(_songSearchProvider));

  void _backToSetlists() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(RoutePaths.setlists);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = ref.watch(canManageSongsProvider);
    final asyncSongs = ref.watch(groupSongsProvider);
    final songs = ref.watch(songsListProvider);
    final query = ref.watch(_songSearchProvider);
    final category = ref.watch(_songCategoryProvider);

    final categories = <String>{
      for (final s in songs) s.category,
    }.toList()
      ..sort();
    final selectedCategory = categories.contains(category) ? category : null;

    final filtered = songs.where((s) {
      final q = query.toLowerCase().trim();
      final matchesQuery = q.isEmpty ||
          s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q);
      final matchesCategory =
          selectedCategory == null || s.category == selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList();

    return PopScope(
        // Use this page's history, not a pushed editor's history above it.
        canPop: ModalRoute.of(context)?.canPop ?? false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _backToSetlists();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: _backToSetlists),
            title: const Text('Song Library'),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: 'New Song',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => context.push(RoutePaths.songCreate),
                ),
            ],
          ),
          body: asyncSongs.isLoading
              ? const Center(child: CircularProgressIndicator())
              : asyncSongs.hasError
                  ? Center(
                      child: Text('Could not load songs: ${asyncSongs.error}'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by title or artist',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () {
                                      _searchController.clear();
                                      ref
                                          .read(_songSearchProvider.notifier)
                                          .state = '';
                                    },
                                  ),
                          ),
                          onChanged: (v) =>
                              ref.read(_songSearchProvider.notifier).state = v,
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _CategoryChip(
                                label: 'All',
                                selected: selectedCategory == null,
                                onTap: () => ref
                                    .read(_songCategoryProvider.notifier)
                                    .state = null,
                              ),
                              const SizedBox(width: 8),
                              for (final c in categories) ...[
                                _CategoryChip(
                                  label: c,
                                  selected: selectedCategory == c,
                                  onTap: () => ref
                                      .read(_songCategoryProvider.notifier)
                                      .state = c,
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.search_off_rounded,
                                  size: 48,
                                  color: AppColors.lightSecondaryText,
                                ),
                                const SizedBox(height: 12),
                                Text('No songs found',
                                    style: theme.textTheme.titleMedium),
                              ],
                            ),
                          )
                        else
                          for (final s in filtered) ...[
                            _SongListTile(song: s),
                            const SizedBox(height: 10),
                          ],
                      ],
                    ),
        ));
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: theme.colorScheme.primary,
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: selected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
      ),
    );
  }
}

class _SongListTile extends StatelessWidget {
  const _SongListTile({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arr = song.primaryArrangement;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(RoutePaths.songDetailsFor(song.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            song.title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (song.isFavorite)
                          const Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: AppColors.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(song.artist, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Pill(label: 'Key ${song.defaultKey}'),
                        _Pill(label: arr.name),
                        _Pill(label: '${arr.bpm} BPM'),
                        _Pill(label: song.category),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
