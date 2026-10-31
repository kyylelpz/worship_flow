
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const WorshipFlowApp());
}

class WorshipFlowApp extends StatelessWidget {
  const WorshipFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worship Flow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF172C53),
        useMaterial3: true,
      ),
      home: const FirebaseConnectionScreen(),
    );
  }
}

class FirebaseConnectionScreen extends StatefulWidget {
  const FirebaseConnectionScreen({super.key});

  @override
  State<FirebaseConnectionScreen> createState() =>
      _FirebaseConnectionScreenState();
}

class _FirebaseConnectionScreenState
    extends State<FirebaseConnectionScreen> {
  bool isLoading = true;
  bool isConnected = false;
  String message = 'Initializing Firebase...';
  String projectId = '';

  @override
  void initState() {
    super.initState();
    checkFirebase();
  }

  Future<void> checkFirebase() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        message = 'Initializing Firebase...';
      });
    }

    try {
      final app = Firebase.apps.isNotEmpty
          ? Firebase.app()
          : await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      if (!mounted) return;

      setState(() {
        isConnected = true;
        projectId = app.options.projectId;
        message = 'Firebase initialized successfully!';
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isConnected = false;
        message = 'Firebase initialization failed:\n$e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worship Flow'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isConnected
                    ? Icons.check_circle
                    : Icons.cloud_off,
                size: 80,
                color: isLoading
                    ? Colors.grey
                    : isConnected
                    ? Colors.green
                    : Colors.red,
              ),
              const SizedBox(height: 24),

              Text(
                isLoading
                    ? 'Connecting...'
                    : isConnected
                    ? 'Connected'
                    : 'Connection Failed',
                style: Theme.of(context).textTheme.headlineMedium,
              ),

              const SizedBox(height: 12),

              if (isLoading)
                const CircularProgressIndicator()
              else
                Text(
                  message,
                  textAlign: TextAlign.center,
                ),

              if (isConnected) ...[
                const SizedBox(height: 16),
                Text(
                  'Firebase Project: $projectId',
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 32),

              FilledButton.icon(
                onPressed: isLoading ? null : checkFirebase,
                icon: const Icon(Icons.refresh),
                label: const Text('Check Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
