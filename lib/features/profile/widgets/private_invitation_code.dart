import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_providers.dart';

class PrivateInvitationCode extends ConsumerStatefulWidget {
  const PrivateInvitationCode({super.key});
  @override
  ConsumerState<PrivateInvitationCode> createState() =>
      _PrivateInvitationCodeState();
}

class _PrivateInvitationCodeState extends ConsumerState<PrivateInvitationCode> {
  String? _code, _error;
  bool _loading = false;
  Future<void> _toggle() async {
    if (_code != null) {
      setState(() => _code = null);
      return;
    }
    final repository = ref.read(authRepositoryProvider);
    if (repository is! AccountProfileRepository) {
      setState(() => _error =
          'Private codes are available with the Firebase account backend.');
      return;
    }
    final uid = ref.read(currentUserProvider)?.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await (repository as AccountProfileRepository).getPrivateInvitationCode();
      if (mounted && ref.read(currentUserProvider)?.id == uid) {
        setState(() => _code = code);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
            title: const Text('Private Invitation Code'),
            subtitle:
                Text(_code ?? '•••••', key: const ValueKey('invitation-code')),
            trailing: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    tooltip: _code == null
                        ? 'Reveal invitation code'
                        : 'Hide invitation code',
                    icon: Icon(_code == null
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: _toggle)),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
      ]);
}
