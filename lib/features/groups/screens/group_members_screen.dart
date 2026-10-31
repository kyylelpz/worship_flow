import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/group_member.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/group_providers.dart';

class GroupMembersScreen extends ConsumerWidget {
  const GroupMembersScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupByIdProvider(groupId));
    final role = ref.watch(roleInGroupProvider(groupId));
    final canManage = role?.canManageMembers ?? false;
    final theme = Theme.of(context);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Members')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${group.name} — Members'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: group.members.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    '${group.memberCount} members',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (!canManage)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Read-only',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            );
          }
          final member = group.members[i - 1];
          return _MemberTile(
            groupId: groupId,
            member: member,
            canManage: canManage,
          );
        },
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.groupId,
    required this.member,
    required this.canManage,
  });

  final String groupId;
  final GroupMember member;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = member.user;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Text(
            user.avatarInitials,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(user.fullName),
        subtitle: Text(user.instrument),
        trailing: canManage
            ? PopupMenuButton<UserRole>(
                tooltip: 'Change role',
                initialValue: member.role,
                onSelected: (newRole) {
                  if (newRole == member.role) return;
                  ref.read(groupRepositoryProvider).updateMemberRole(
                        groupId: groupId,
                        userId: user.id,
                        role: newRole,
                      );
                },
                itemBuilder: (_) => [
                  for (final r in UserRole.values)
                    PopupMenuItem<UserRole>(
                      value: r,
                      child: Text(r.label),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _roleColor(member.role).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    member.role.label,
                    style: TextStyle(
                      color: _roleColor(member.role),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _roleColor(member.role).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  member.role.label,
                  style: TextStyle(
                    color: _roleColor(member.role),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
      ),
    );
  }

  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.administrator:
        return AppColors.danger;
      case UserRole.worshipLeader:
        return AppColors.accent;
      case UserRole.worshipTrainee:
        return AppColors.success;
    }
  }
}
