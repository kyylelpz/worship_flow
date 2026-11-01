import '../../../core/cache/cache_providers.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../groups/providers/group_providers.dart';
import '../providers/setlist_providers.dart';
import '../../groups/providers/invitation_providers.dart';
import '../widgets/setlist_card.dart';
import '../widgets/setlist_filter_bar.dart';
import '../widgets/upcoming_service_card.dart';

class SetlistsScreen extends ConsumerWidget {
  const SetlistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(selectedGroupProvider);
    final role = ref.watch(currentRoleProvider);
    final canEdit = role?.canManageSetlists ?? false;
    final asyncSetlists = ref.watch(filteredSetlistsProvider);
    final filter = ref.watch(setlistFilterProvider);
    final theme = Theme.of(context);
    ref.watch(cacheChangesProvider);
    final groupId = ref.watch(selectedGroupIdProvider);
    final cache = ref.watch(localContentCacheProvider);
    final cached = cache != null && groupId != null && cache.isOffline(groupId);

    Future<void> openCreate() async {
      if (group == null) return;

      await context.push(RoutePaths.setlistEditorFor('new'));
    }

    return Scaffold(
      appBar: AppBar(
        bottom: cached
            ? const PreferredSize(
                preferredSize: Size.fromHeight(32),
                child: Padding(
                    padding: EdgeInsets.all(6),
                    child:
                        Text('Offline · Fully cached published setlists only')))
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group?.name ?? 'Setlists'),
            if (group != null)
              Text(
                group.churchName,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Song Library',
            icon: const Icon(Icons.library_music_rounded),
            onPressed: () => context.push(RoutePaths.songs),
          ),
          IconButton(
            tooltip: 'Profile',
            icon: Badge(
                isLabelVisible: (ref
                                .watch(pendingInvitationsProvider)
                                .valueOrNull
                                ?.length ??
                            0) +
                        (ref
                                .watch(membershipNotificationsProvider)
                                .valueOrNull
                                ?.length ??
                            0) >
                    0,
                child: const Icon(Icons.person_rounded)),
            onPressed: () => context.push(RoutePaths.profile),
          ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: openCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Setlist'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          final groupId = ref.read(selectedGroupIdProvider);
          if (groupId != null) {
            ref.invalidate(groupSetlistsProvider);
          }
          await ref.read(groupSetlistsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            const SetlistFilterBar(),
            if (filter == SetlistFilter.upcoming &&
                ref.watch(nextUpcomingSetlistProvider) != null) ...[
              const SizedBox(height: 16),
              const UpcomingServiceCard(),
            ],
            const SizedBox(height: 16),
            asyncSetlists.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Could not load setlists: $e'),
              ),
              data: (setlists) {
                final hasNextUpcoming = filter == SetlistFilter.upcoming &&
                    ref.watch(nextUpcomingSetlistProvider) != null;

                if (setlists.isEmpty) {
                  // If the only upcoming service is the one shown in the UP NEXT card,
                  // don't claim there are no upcoming services.
                  if (hasNextUpcoming && filter == SetlistFilter.upcoming) {
                    return const SizedBox.shrink();
                  }
                  return _EmptyState(
                    filter: filter,
                    canEdit: canEdit,
                    onCreate: canEdit ? openCreate : null,
                  );
                }

                return Column(
                  children: [
                    if (filter == SetlistFilter.upcoming &&
                        hasNextUpcoming) ...[
                      // optional section header: "Later services"
                      const SizedBox(height: 4),
                    ],
                    for (final s in setlists) ...[
                      SetlistCard(setlist: s),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.filter,
    required this.canEdit,
    this.onCreate,
  });

  final SetlistFilter filter;
  final bool canEdit;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, subtitle) = switch (filter) {
      SetlistFilter.upcoming => (
          Icons.event_available_rounded,
          'No upcoming services',
          'Create a setlist to get the team ready.',
        ),
      SetlistFilter.previous => (
          Icons.history_rounded,
          'No previous services',
          'Once a service is published and passes, it will show here.',
        ),
      SetlistFilter.drafts => (
          Icons.edit_note_rounded,
          'No drafts',
          'Drafts appear here while you\'re still planning.',
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.lightSecondaryText),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (canEdit && onCreate != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Setlist'),
            ),
          ],
        ],
      ),
    );
  }
}
