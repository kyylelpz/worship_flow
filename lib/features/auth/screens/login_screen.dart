import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/session_state.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _pressed = false;

  Future<void> _handleSignIn() async {
    setState(() => _pressed = true);
    await ref.read(sessionProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    setState(() => _pressed = false);
    // Router's redirect will navigate. No context.go needed.
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);
    final isLoading = session.isLoading || _pressed;

    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BrandMark(color: theme.colorScheme.primary),
                  const SizedBox(height: 24),
                  Text(
                    'WorshipFlow',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Every Note for His Glory',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.lightSecondaryText,
                    ),
                  ),
                  const SizedBox(height: 56),
                  _GoogleSignInButton(
                    isLoading: isLoading,
                    onPressed: _handleSignIn,
                  ),
                  if (session.errorMessage != null) ...[
                    Text(session.errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error)),
                    TextButton(
                        onPressed: isLoading
                            ? null
                            : () => ref
                                .read(sessionProvider.notifier)
                                .retrySession(),
                        child: const Text('Retry account loading')),
                    TextButton(
                        onPressed: isLoading
                            ? null
                            : () =>
                                ref.read(sessionProvider.notifier).signOut(),
                        child: const Text('Sign out')),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    ref.watch(useMockBackendProvider)
                        ? 'Development mock sign-in — no Firebase account is created.'
                        : 'Sign in securely with your Google account.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            )),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(
          Icons.music_note_rounded,
          color: Colors.white,
          size: 44,
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: theme.colorScheme.surface,
          side: BorderSide(color: theme.colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleGlyph(color: theme.colorScheme.onSurface),
                  const SizedBox(width: 12),
                  Flexible(
                      child: Text(
                    'Continue with Google',
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
                ],
              ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // Simple monochrome 'G' glyph — avoids shipping Google's colored asset
    // before branding assets land in Phase 2.
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        'G',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
