import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_repository.dart';

/// Keep diagnostics useful without serializing credentials, account objects or
/// exception.details (which may contain native payloads).
String redactAuthDiagnostic(String text) => text
    .replaceAll(
        RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false), 'Bearer [REDACTED]')
    .replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
        '[REDACTED]')
    .replaceAll(
        RegExp(
            r'''["']?(?:id[_-]?token|access[_-]?token|refresh[_-]?token|server[_-]?auth[_-]?code|authorization|credentials?|password|client[_-]?secret|api[_-]?key|code)["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;&]+)''',
            caseSensitive: false),
        '[REDACTED]')
    .replaceAll(
        RegExp(
            r'(?<![A-Za-z0-9_/.:-])[A-Za-z0-9_+/-]{40,}(?![A-Za-z0-9_/.:-])'),
        '[REDACTED]');

void logGoogleSignInFailure(Object error, StackTrace stack, String stage) {
  if (!kDebugMode) return;
  final (code, message) = switch (error) {
    GoogleSignInException e => (
        e.code.name,
        e.description ?? '(no description)'
      ),
    FirebaseAuthException e => (e.code, e.message ?? '(no message)'),
    PlatformException e => (e.code, e.message ?? '(no message)'),
    AccountException e => ('account', e.message),
    // Arbitrary toString() implementations may include credentials.
    _ => ('unknown', 'Unclassified failure; raw payload omitted'),
  };
  debugPrint(redactAuthDiagnostic(
      '[Google Sign-In][$stage] ${error.runtimeType} code[$code] message=$message'));
  // Keep the complete trace, including native/non-Dart frames, without passing
  // it through Flutter's stack-frame parser or serializing the exception.
  debugPrint(redactAuthDiagnostic('$stack'));
}

Exception googleSignInFailure(GoogleSignInException error) {
  if (error.code == GoogleSignInExceptionCode.canceled) {
    // Credential Manager can also report configuration failures as canceled;
    // there is no reliable signal to distinguish those from user cancellation.
    return const SignInCancelled();
  }
  final description = error.description ?? '';
  if (RegExp(
          r'serverClientId.*(?:must|required|missing)|(?:missing|required).*serverClientId',
          caseSensitive: false)
      .hasMatch(description)) {
    return const AccountException(
        'Google Sign-In is missing its Web OAuth client configuration. Download the updated google-services.json, remove stale Android configuration overrides, and rebuild the app.');
  }
  if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
      RegExp(r'developer_error|ApiException:\s*10\b|statusCode\s*[=:]\s*10\b',
              caseSensitive: false)
          .hasMatch(description)) {
    return const AccountException(
        'Google Sign-In has an Android developer configuration error. Verify the application ID, signing SHA and Web OAuth client belong to the same Firebase project, then rebuild.');
  }
  if (RegExp(
          r'network|SocketException|UnknownHost|unable to resolve host|timed?\s*out|ApiException:\s*7\b|statusCode\s*[=:]\s*7\b',
          caseSensitive: false)
      .hasMatch(description)) {
    return const AccountException(
        'Google Sign-In could not connect. Check your internet connection and try again.');
  }
  if (error.code == GoogleSignInExceptionCode.providerConfigurationError) {
    return const AccountException(
        'Google Sign-In is unavailable on this device. Check that Google Play services and a Google credential provider are installed and up to date.');
  }
  if (error.code == GoogleSignInExceptionCode.interrupted ||
      error.code == GoogleSignInExceptionCode.uiUnavailable) {
    return const AccountException(
        'Google Sign-In was interrupted or could not open. Return to the app and try again.');
  }
  return const AccountException(
      'Google Sign-In could not complete. Please try again. Debug builds record the error code and diagnostic message.');
}

Exception firebaseGoogleSignInFailure(FirebaseAuthException error) {
  return switch (error.code) {
    'popup-closed-by-user' ||
    'cancelled-popup-request' ||
    'web-context-cancelled' =>
      const SignInCancelled(),
    'network-request-failed' => const AccountException(
        'Google Sign-In could not connect to Firebase. Check your internet connection and try again.'),
    'operation-not-allowed' => const AccountException(
        'Google Sign-In is disabled for this Firebase project. Enable Google in Firebase Authentication.'),
    'invalid-credential' || 'invalid-oauth-client-id' => const AccountException(
        'Firebase rejected the Google sign-in credential. Verify the Web OAuth client and Android app configuration belong to this Firebase project.'),
    'user-disabled' => const AccountException(
        'This account has been disabled. Contact the project administrator.'),
    _ => const AccountException(
        'Firebase could not finish Google Sign-In. Please try again. Debug builds record the Firebase error code.'),
  };
}
