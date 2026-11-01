import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/firebase/firebase_providers.dart';
import 'group_creation_screen.dart';
import '../../../core/models/worship_group.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/group_providers.dart';

class GroupSelectionScreen extends ConsumerWidget {
  const GroupSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final groupsAsync = ref.watch(userGroupsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a Group'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
      floatingActionButton:
          ref.watch(useMockBackendProvider) ? const _DevRoleFab() : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userGroupsProvider);
          await ref.read(userGroupsProvider.future);
        },
        child: groupsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(message: e.toString()),
          data: (groups) {
            if (groups.isEmpty) {
              return const _EmptyGroupsState();
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                Text(
                  'Welcome, ${session.user?.firstName ?? 'Friend'}',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a group to continue.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.lightSecondaryText,
                  ),
                ),
                const SizedBox(height: 20),
                for (final g in groups) ...[
                  _GroupTile(group: g),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                const _JoinOrCreateCard(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.group});

  final WorshipGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final membership = ref.watch(currentMembershipProvider(group.id));
    final accent = Color(group.accentColorValue);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          ref.read(sessionProvider.notifier).selectGroup(group.id);
          // Router redirect will move us to /setlists automatically.
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.groups_rounded,
                  color: accent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      group.churchName,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            membership?.role.label ?? '—',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${group.memberCount} members',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.lightSecondaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinOrCreateCard extends StatelessWidget {
  const _JoinOrCreateCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Not seeing your group?',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Create a worship team. Invitation-based joining is coming in the next phase.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: () => Navigator.of(context).push<String>(
                    MaterialPageRoute(
                        builder: (_) => const GroupCreationScreen())),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Group')),
          ],
        ),
      ),
    );
  }
}

class _EmptyGroupsState extends StatelessWidget {
  const _EmptyGroupsState();

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(24), children: const [
      Text(
          'You have no worship groups yet. Create your first group to continue.'),
      SizedBox(height: 20),
      _JoinOrCreateCard(),
    ]);
  }
}

class _ErrorState extends ConsumerWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.all(32), children: [
      Text('Something went wrong:\n$message', textAlign: TextAlign.center),
      TextButton(
          onPressed: () {
            ref.invalidate(userGroupsProvider);
            ref.invalidate(allGroupsProvider);
          },
          child: const Text('Retry')),
    ]);
  }
}

/// Developer-only role switcher. Deliberately ugly-labeled to signal it
/// only rendered with explicit development mocks, never Firebase mode.
class _DevRoleFab extends ConsumerWidget {
  const _DevRoleFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentRoleProvider) ?? UserRole.administrator;

    return FloatingActionButton.extended(
      heroTag: 'dev-role-fab',
      backgroundColor: AppColors.warning,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.developer_mode_rounded),
      label: Text('DEV · ${role.label}'),
      onPressed: () => _showRoleSheet(context, ref),
    );
  }

  void _showRoleSheet(BuildContext context, WidgetRef ref) {
    final current = ref.read(currentRoleProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Developer Role Switcher',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'For testing only. Does not change the underlying user.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                RadioGroup<UserRole>(
                  groupValue: current,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(sessionProvider.notifier).setRoleForTesting(v);
                      Navigator.of(ctx).pop();
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final r in UserRole.values)
                        RadioListTile<UserRole>(
                          value: r,
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.label),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    ref.read(sessionProvider.notifier).clearGroup();
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Clear selected group'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
