import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/membership_position.dart';
import '../data/group_repository.dart';
import '../providers/group_providers.dart';

class GroupCreationScreen extends ConsumerStatefulWidget {
  const GroupCreationScreen({super.key});
  @override
  ConsumerState<GroupCreationScreen> createState() =>
      _GroupCreationScreenState();
}

class _GroupCreationScreenState extends ConsumerState<GroupCreationScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _church = TextEditingController(),
      _custom = TextEditingController();
  final _requestId = const Uuid().v4();
  MembershipPosition? _position;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _church.dispose();
    _custom.dispose();
    super.dispose();
  }

  String? _text(String? value, int max) => value == null || value.trim().isEmpty
      ? 'Required.'
      : value.trim().length > max || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
          ? 'Use at most $max characters without control characters.'
          : null;
  Future<void> _create() async {
    if (!_form.currentState!.validate() || _saving) return;
    final repository = ref.read(groupRepositoryProvider);
    if (repository is! GroupCreationRepository) {
      setState(
          () => _error = 'Group creation is unavailable in this repository.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await (repository as GroupCreationRepository).createGroupWithPosition(
          name: _name.text.trim(),
          churchName: _church.text.trim(),
          position: _position!,
          customPosition:
              _position == MembershipPosition.other ? _custom.text.trim() : '',
          requestId: _requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Group created. You are its Administrator.')));
        Navigator.pop(context, id);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: Scaffold(
          appBar: AppBar(title: const Text('Create Group')),
          body: Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                const Text(
                    'You will become Administrator of the new group. Your position is separate from your role.'),
                const SizedBox(height: 20),
                TextFormField(
                    controller: _name,
                    readOnly: _saving,
                    decoration: const InputDecoration(labelText: 'Group name'),
                    validator: (v) => _text(v, 120)),
                const SizedBox(height: 16),
                TextFormField(
                    controller: _church,
                    readOnly: _saving,
                    decoration: const InputDecoration(labelText: 'Church name'),
                    validator: (v) => _text(v, 160)),
                const SizedBox(height: 16),
                DropdownButtonFormField<MembershipPosition>(
                    initialValue: _position,
                    decoration:
                        const InputDecoration(labelText: 'Your position'),
                    items: [
                      for (final p in MembershipPosition.values)
                        DropdownMenuItem(value: p, child: Text(p.label))
                    ],
                    validator: (v) =>
                        v == null ? 'Choose your position.' : null,
                    onChanged:
                        _saving ? null : (v) => setState(() => _position = v)),
                if (_position == MembershipPosition.other) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _custom,
                      readOnly: _saving,
                      decoration:
                          const InputDecoration(labelText: 'Custom position'),
                      validator: (v) => _text(v, 80)),
                ],
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: _saving ? null : _create,
                    child: Text(_saving ? 'Creating…' : 'Create Group')),
              ]))));
}
