import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:worship_flow/features/auth/data/auth_repository.dart';
import 'package:worship_flow/features/auth/data/google_sign_in_failures.dart';

String message(Exception exception) => (exception as AccountException).message;
void main() {
  test('7.x cancellation stays quiet, including ambiguous Android cancellation',
      () {
    expect(
        googleSignInFailure(const GoogleSignInException(
            code: GoogleSignInExceptionCode.canceled)),
        isA<SignInCancelled>());
  });
  test('missing Web OAuth configuration has an actionable distinct message',
      () {
    final error = googleSignInFailure(const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'serverClientId must be provided on Android'));
    expect(message(error), contains('missing its Web OAuth client'));
    expect(message(error), contains('rebuild'));
  });
  test('developer configuration errors distinguish package/SHA/client failures',
      () {
    for (final error in [
      const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError),
      const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'DEVELOPER_ERROR'),
      const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'ApiException: 10:'),
    ]) {
      expect(message(googleSignInFailure(error)),
          contains('developer configuration error'));
    }
  });
  test(
      'network failures remain retryable and are not described as SHA problems',
      () {
    for (final detail in [
      'NETWORK_ERROR',
      'Unable to resolve host',
      'ApiException: 7:',
      'connection timed out'
    ]) {
      final result = message(googleSignInFailure(GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError, description: detail)));
      expect(result, contains('internet connection'));
      expect(result, isNot(contains('SHA')));
    }
    expect(
        message(firebaseGoogleSignInFailure(
            FirebaseAuthException(code: 'network-request-failed'))),
        contains('internet connection'));
  });
  test('provider, interrupted and unknown errors have distinct safe fallbacks',
      () {
    expect(
        message(googleSignInFailure(const GoogleSignInException(
            code: GoogleSignInExceptionCode.providerConfigurationError))),
        contains('Google Play services'));
    expect(
        message(googleSignInFailure(const GoogleSignInException(
            code: GoogleSignInExceptionCode.interrupted))),
        contains('interrupted'));
    expect(
        message(googleSignInFailure(const GoogleSignInException(
            code: GoogleSignInExceptionCode.uiUnavailable))),
        contains('could not open'));
    expect(
        message(googleSignInFailure(const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            details: 'private payload'))),
        isNot(contains('private payload')));
  });
  test(
      'Firebase rejects disabled provider, invalid credential and cancellation distinctly',
      () {
    expect(
        message(firebaseGoogleSignInFailure(
            FirebaseAuthException(code: 'operation-not-allowed'))),
        contains('Enable Google'));
    expect(
        message(firebaseGoogleSignInFailure(
            FirebaseAuthException(code: 'invalid-credential'))),
        contains('Web OAuth client'));
    expect(
        message(firebaseGoogleSignInFailure(
            FirebaseAuthException(code: 'user-disabled'))),
        contains('disabled'));
    for (final code in [
      'popup-closed-by-user',
      'cancelled-popup-request',
      'web-context-cancelled'
    ]) {
      expect(firebaseGoogleSignInFailure(FirebaseAuthException(code: code)),
          isA<SignInCancelled>());
    }
  });
  test(
      'debug diagnostics preserve exception type, code, description, stage and stack',
      () {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (String? value, {int? wrapWidth}) {
      if (value != null) lines.add(value);
    };
    addTearDown(() => debugPrint = original);
    const frame =
        '#0 FirebaseAuthRepository.signInWithGoogle (package:worship_flow/features/auth/data/firebase_auth_repository.dart:134:27)';
    logGoogleSignInFailure(
        const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
            description: 'serverClientId must be provided on Android',
            details: {'idToken': 'never-log-details'}),
        StackTrace.fromString(frame),
        'google-authenticate');
    final log = lines.join('\n');
    expect(log, contains('GoogleSignInException'));
    expect(log, contains('code[clientConfigurationError]'));
    expect(log, contains('serverClientId must be provided on Android'));
    expect(log, contains('[google-authenticate]'));
    expect(log, contains(frame));
    expect(log, isNot(contains('never-log-details')));
  });
  test(
      'diagnostics redact token fields, auth codes, Bearer and JWT without losing stack paths',
      () {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJleGFtcGxlIn0.c2lnbmF0dXJl';
    final output = redactAuthDiagnostic(
        'network_error access_token=access-secret idToken="id-secret" refreshToken=refresh-secret serverAuthCode=server-secret credential=credential-secret authorization=Bearer bearer-secret code=code-secret $jwt');
    for (final secret in [
      'access-secret',
      'id-secret',
      'refresh-secret',
      'server-secret',
      'credential-secret',
      'bearer-secret',
      'code-secret',
      jwt
    ]) {
      expect(output, isNot(contains(secret)));
    }
    expect(output, contains('network_error'));
  });
  test('Firebase diagnostics never serialize credential or email properties',
      () {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (String? value, {int? wrapWidth}) {
      if (value != null) lines.add(value);
    };
    addTearDown(() => debugPrint = original);
    logGoogleSignInFailure(
        FirebaseAuthException(
            code: 'invalid-credential',
            message: 'Credential was rejected',
            email: 'private@example.test',
            credential:
                GoogleAuthProvider.credential(idToken: 'private-id-token')),
        StackTrace.fromString('#0 credential exchange'),
        'firebase-credential');
    final log = lines.join('\n');
    expect(log, contains('code[invalid-credential]'));
    expect(log, contains('Credential was rejected'));
    expect(log, isNot(contains('private-id-token')));
    expect(log, isNot(contains('private@example.test')));
  });
}
