import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'data/store.dart';
import 'ui/admin.dart';
import 'ui/shared.dart';
import 'services/firebase_startup.dart';

// A separate entry point so the admin panel compiles into its own web
// bundle, reachable only at its own build/deploy target, never from the
// customer app. Build with: flutter build web -t lib/main_admin.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  var live = false;
  String? startupError;
  if (project.isNotEmpty) {
    try {
      await Firebase.initializeApp(options: firebaseOptions);
      live = true;
    } catch (e) {
      startupError =
          'Firebase could not start. Check the supplied project configuration and restart.';
    }
  }
  if (startupError != null) {
    runApp(
      MaterialApp(home: Scaffold(body: Center(child: Text(startupError)))),
    );
    return;
  }
  final firestore = live ? FirebaseFirestore.instance : null;
  final store = Store(live: live, database: firestore);
  await store.init();
  runApp(AdminApp(store: store));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Business studio',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b50)),
      ),
      home: !store.live
          ? AdminPage(store: store)
          : store.user == null
          ? AdminLoginPage(store: store)
          : !store.admin
          ? AdminAccessDeniedPage(store: store)
          : AdminPage(store: store),
    ),
  );
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await widget.store.login(email.text.trim(), password.text);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business studio')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sign in with your administrator email and password.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Email address'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) {
                  if (!busy) submit();
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Signing in…' : 'Sign in'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AdminAccessDeniedPage extends StatelessWidget {
  const AdminAccessDeniedPage({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business studio')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This account is not an administrator for this business.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: store.logout,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}
