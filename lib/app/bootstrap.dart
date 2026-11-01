import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../firebase_options.dart';
import '../core/firebase/firebase_providers.dart';

Future<void> bootstrap(Widget Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (!useDevelopmentMocks) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: false);
      if (kIsWeb) await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      if (!kReleaseMode &&
          const bool.fromEnvironment('WF_FIREBASE_EMULATORS')) {
        const configured = String.fromEnvironment('WF_EMULATOR_HOST');
        final host = configured.isNotEmpty
            ? configured
            : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                ? '10.0.2.2'
                : '127.0.0.1';
        await FirebaseAuth.instance.useAuthEmulator(host, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
        FirebaseFunctions.instanceFor(region: 'asia-east2')
            .useFunctionsEmulator(host, 5001);
      }
    }
    runApp(builder());
  } catch (_) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: SafeArea(
                child: Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Firebase could not start. Check platform configuration and connection, then restart Worship Flow.')))))));
  }
}
