import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../widgets/private_invitation_code.dart';

class ProfileCompletionScreen extends ConsumerStatefulWidget {
  const ProfileCompletionScreen({super.key});
  @override
  ConsumerState<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState
    extends ConsumerState<ProfileCompletionScreen> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(
      text: ref.read(currentUserProvider)?.firstName ?? '');
  late final _last = TextEditingController(
      text: ref.read(currentUserProvider)?.lastName ?? '');
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  String? _name(String? value) => value == null || value.trim().isEmpty
      ? 'Required.'
      : value.trim().length > 80 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
          ? 'Use at most 80 characters without control characters.'
          : null;
  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .completeProfile(_first.text.trim(), _last.text.trim());
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (previous, next) {
      if (previous?.id != next?.id && next != null) {
        _first.text = next.firstName;
        _last.text = next.lastName;
        _error = null;
      }
    });
    final user = ref.watch(currentUserProvider);
    return Scaffold(
        appBar: AppBar(title: const Text('Complete your profile'), actions: [
          IconButton(
              tooltip: 'Sign out',
              onPressed: _saving
                  ? null
                  : () => ref.read(sessionProvider.notifier).signOut(),
              icon: const Icon(Icons.logout)),
        ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Form(
                    key: _form,
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      const Text(
                          'Confirm your name before accessing worship groups.'),
                      const SizedBox(height: 20),
                      TextFormField(
                          controller: _first,
                          readOnly: _saving,
                          decoration:
                              const InputDecoration(labelText: 'First Name'),
                          validator: _name),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _last,
                          readOnly: _saving,
                          decoration:
                              const InputDecoration(labelText: 'Last Name'),
                          validator: _name),
                      const SizedBox(height: 16),
                      TextFormField(
                          key: ValueKey('email-${user?.id}'),
                          initialValue: user?.email ?? '',
                          readOnly: true,
                          decoration: const InputDecoration(
                              labelText: 'Email',
                              helperText: 'From your verified Google account')),
                      const SizedBox(height: 16),
                      PrivateInvitationCode(key: ValueKey(user?.id)),
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving…' : 'Save Profile')),
                    ])))));
  }
}
