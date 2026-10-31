import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../../groups/providers/group_providers.dart';
import '../providers/setlist_providers.dart';
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

    Future<void> openCreate() async {
      if (group == null) return;
      final now = DateTime.now();
      final suggestedDate = DateTime(now.year, now.month, now.day + 7, 9, 30);
      final id = await ref.read(setlistRepositoryProvider).createDraft(
            groupId: group.id,
            name: 'New Setlist',
            serviceDateTime: suggestedDate,
          );
      if (context.mounted) {
        unawaited(context.push(RoutePaths.setlistEditorFor(id)));
      }
    }

    return Scaffold(
      appBar: AppBar(
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
            icon: const Icon(Icons.person_rounded),
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
            if (filter == SetlistFilter.upcoming) ...[
              const UpcomingServiceCard(),
              const SizedBox(height: 16),
            ],
            const SetlistFilterBar(),
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
                if (setlists.isEmpty) {
                  return _EmptyState(
                    filter: filter,
                    canEdit: canEdit,
                    onCreate: canEdit ? openCreate : null,
                  );
                }
                return Column(
                  children: [
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
