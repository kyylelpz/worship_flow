import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_providers.dart';
import '../../groups/providers/invitation_providers.dart';
import '../../groups/data/invitation_repository.dart';

Future<bool> confirmMembershipAction(BuildContext context, String title,
        String message, String action) async =>
    await showDialog<bool>(
        context: context,
        builder: (ctx) =>
            AlertDialog(title: Text(title), content: Text(message), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(action)),
            ])) ??
    false;

class InvitationPrivacyToggle extends ConsumerStatefulWidget {
  const InvitationPrivacyToggle({super.key});
  @override
  ConsumerState<InvitationPrivacyToggle> createState() =>
      _InvitationPrivacyToggleState();
}

class _InvitationPrivacyToggleState
    extends ConsumerState<InvitationPrivacyToggle> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(invitationRepositoryProvider);
    if (repository == null) return const SizedBox.shrink();
    return Card(
        child: SwitchListTile(
            title: const Text('Allow Invitations'),
            value: ref.watch(currentUserProvider)?.allowInvitations ?? true,
            onChanged: _saving
                ? null
                : (allow) async {
                    setState(() => _saving = true);
                    try {
                      await repository.setAllowInvitations(allow);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  }));
  }
}

class InvitationPanel extends ConsumerStatefulWidget {
  const InvitationPanel({super.key});
  @override
  ConsumerState<InvitationPanel> createState() => _InvitationPanelState();
}

class _InvitationPanelState extends ConsumerState<InvitationPanel> {
  final _busy = <String>{};
  Future<void> _respond(GroupInvitation i, bool accept) async {
    final action = accept ? 'Accept' : 'Decline';
    if (!await confirmMembershipAction(context, '$action invitation?',
            '${i.groupName}\n${i.role.label} · ${i.positionLabel}', action) ||
        !mounted) {
      return;
    }
    final repository = ref.read(invitationRepositoryProvider);
    if (repository == null) return;
    setState(() => _busy.add(i.groupId));
    try {
      await repository.respond(i, accept: accept);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(accept
                ? 'Invitation accepted. The group is available in Group Selection.'
                : 'Invitation declined.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(i.groupId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingInvitationsProvider);
    final notices = ref.watch(membershipNotificationsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      pending.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ListTile(
              title: const Text('Could not load invitation requests'),
              subtitle: Text('$e'),
              trailing: IconButton(
                  tooltip: 'Retry invitations',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(pendingInvitationsProvider))),
          data: (items) => Column(children: [
                for (final i in items)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Invitation Request',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                Text(i.groupName),
                                Text('${i.role.label} · ${i.positionLabel}'),
                                Wrap(spacing: 8, children: [
                                  FilledButton(
                                      onPressed: _busy.contains(i.groupId)
                                          ? null
                                          : () => _respond(i, true),
                                      child: const Text('Accept')),
                                  TextButton(
                                      onPressed: _busy.contains(i.groupId)
                                          ? null
                                          : () => _respond(i, false),
                                      child: const Text('Decline')),
                                ])
                              ])))
              ])),
      notices.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => ListTile(
              title: const Text('Could not load membership notifications'),
              trailing: IconButton(
                  tooltip: 'Retry notifications',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.invalidate(membershipNotificationsProvider))),
          data: (items) => Column(children: [
                for (final n in items)
                  Card(
                      child: ListTile(
                          leading:
                              const Icon(Icons.notifications_active_outlined),
                          title: Text('Invitation accepted · ${n.groupName}'),
                          subtitle: const Text(
                              'A recipient accepted your invitation.'),
                          trailing: IconButton(
                              tooltip: 'Dismiss notification',
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(invitationRepositoryProvider)
                                      ?.markRead(n.id);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e')));
                                  }
                                }
                              })))
              ])),
    ]);
  }
}
