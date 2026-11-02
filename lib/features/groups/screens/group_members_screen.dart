import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/membership_position.dart';
import '../../../core/models/user_role.dart';
import '../../../core/router/route_paths.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/widgets/invitation_panel.dart';
import '../data/invitation_repository.dart';
import '../providers/group_providers.dart';
import '../providers/invitation_providers.dart';

class GroupMembersScreen extends ConsumerWidget {
  const GroupMembersScreen({super.key, required this.groupId});
  final String groupId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupByIdProvider(groupId));
    final canManage =
        ref.watch(roleInGroupProvider(groupId))?.canManageMembers == true;
    final repository = ref.watch(invitationRepositoryProvider);
    return Scaffold(
        appBar: AppBar(
            title: Text(group == null ? 'Members' : '${group.name} — Members'),
            leading: BackButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(RoutePaths.profile))),
        body: group == null
            ? const Center(
                child: Text('Group unavailable. Return to Group Selection.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                    Text('${group.memberCount} members',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (canManage && repository != null)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                              icon: const Icon(Icons.person_add_alt),
                              label: const Text('Invite Member'),
                              onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => MemberEditorScreen(
                                          groupId: groupId))))),
                    if (!canManage) const Text('Read-only'),
                    for (final m in group.members)
                      Card(
                          child: ListTile(
                        leading:
                            CircleAvatar(child: Text(m.user.avatarInitials)),
                        title: Text(m.user.fullName),
                        subtitle: Text('${m.role.label} · ${m.positionLabel}'),
                        trailing: canManage && repository != null
                            ? PopupMenuButton<String>(
                                tooltip: 'Manage ${m.user.fullName}',
                                onSelected: (action) async {
                                  if (action == 'edit') {
                                    await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                            builder: (_) => MemberEditorScreen(
                                                groupId: groupId, member: m)));
                                    return;
                                  }
                                  if (!await confirmMembershipAction(
                                      context,
                                      'Remove member?',
                                      'Remove ${m.user.fullName} from ${group.name}?',
                                      'Remove')) {
                                    return;
                                  }
                                  try {
                                    await repository.removeMember(
                                        groupId: groupId, uid: m.uid);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                              SnackBar(content: Text('$e')));
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'edit',
                                          child:
                                              Text('Edit role and position')),
                                      PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove member'))
                                    ])
                            : canManage
                                ? PopupMenuButton<UserRole>(
                                    tooltip: 'Change role (development)',
                                    initialValue: m.role,
                                    onSelected: (role) async {
                                      try {
                                        await ref
                                            .read(groupRepositoryProvider)
                                            .updateMemberRole(
                                                groupId: groupId,
                                                userId: m.uid,
                                                role: role);
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text('$e')));
                                        }
                                      }
                                    },
                                    itemBuilder: (_) => [
                                          for (final role in UserRole.values)
                                            PopupMenuItem(
                                                value: role,
                                                child: Text(role.label))
                                        ])
                                : null,
                      )),
                  ]));
  }
}

class MemberEditorScreen extends ConsumerStatefulWidget {
  const MemberEditorScreen({super.key, required this.groupId, this.member});
  final String groupId;
  final GroupMember? member;
  @override
  ConsumerState<MemberEditorScreen> createState() => _MemberEditorScreenState();
}

class _MemberEditorScreenState extends ConsumerState<MemberEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  late final _custom =
      TextEditingController(text: widget.member?.customPosition ?? '');
  late UserRole _role = widget.member?.role ?? UserRole.worshipTrainee;
  late MembershipPosition _position =
      widget.member?.position ?? MembershipPosition.vocalist;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    final repo = ref.read(invitationRepositoryProvider);
    if (repo == null ||
        ref.read(roleInGroupProvider(widget.groupId))?.canManageMembers !=
            true) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.member == null) {
        await repo.invite(
            groupId: widget.groupId,
            email: _email.text,
            role: _role,
            position: _position,
            customPosition: _custom.text.trim());
      } else {
        await repo.updateMember(
            groupId: widget.groupId,
            uid: widget.member!.uid,
            role: _role,
            position: _position,
            customPosition: _custom.text.trim());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            showCloseIcon: true,
            content: Text(widget.member == null
                ? 'Invitation sent. The recipient can respond in WorshipFlow.'
                : 'Member updated.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed =
        ref.watch(roleInGroupProvider(widget.groupId))?.canManageMembers ==
            true;
    final self = widget.member?.uid == ref.watch(currentUserProvider)?.id;
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
            appBar: AppBar(
                title: Text(
                    widget.member == null ? 'Invite Member' : 'Edit Member')),
            body: !allowed
                ? const Center(child: Text('Administrator access is required.'))
                : Form(
                    key: _form,
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      if (widget.member == null)
                        TextFormField(
                            controller: _email,
                            readOnly: _saving,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                                labelText: 'Google email',
                                helperText:
                                    'The recipient must be registered and allow invitations.'),
                            validator: validateInvitationEmail)
                      else
                        Text(widget.member!.user.fullName,
                            style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<UserRole>(
                          initialValue: _role,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: [
                            for (final r in UserRole.values)
                              DropdownMenuItem(value: r, child: Text(r.label))
                          ],
                          onChanged: _saving || self
                              ? null
                              : (r) => setState(() => _role = r!)),
                      if (self)
                        const Text('Your own role cannot be changed here.'),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<MembershipPosition>(
                          initialValue: _position,
                          decoration:
                              const InputDecoration(labelText: 'Position'),
                          items: [
                            for (final p in MembershipPosition.values)
                              DropdownMenuItem(value: p, child: Text(p.label))
                          ],
                          onChanged: _saving
                              ? null
                              : (p) => setState(() => _position = p!)),
                      if (_position == MembershipPosition.other) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: _custom,
                            readOnly: _saving,
                            decoration: const InputDecoration(
                                labelText: 'Custom position'),
                            validator: (v) => v == null ||
                                    v.trim().isEmpty ||
                                    v.trim().length > 80
                                ? 'Enter a position (maximum 80 characters).'
                                : null),
                      ],
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving
                              ? 'Saving…'
                              : widget.member == null
                                  ? 'Send Invitation'
                                  : 'Save Member')),
                    ]))));
  }
}
