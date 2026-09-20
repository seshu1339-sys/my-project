import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'data/store.dart';
import 'services/firebase_startup.dart';
import 'services/emulators.dart';
import 'ui/vendor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  var live = false;
  String? startupError;
  if (project.isNotEmpty) {
    try {
      await Firebase.initializeApp(options: firebaseOptions);
      await connectToEmulatorsIfConfigured();
      live = true;
    } catch (_) {
      startupError = 'Firebase could not start. Check the supplied project configuration.';
    }
  }
  if (startupError != null) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text(startupError)))));
    return;
  }
  final store = Store(live: live, database: live ? FirebaseFirestore.instance : null);
  await store.init();
  runApp(VendorApp(store: store));
}

class VendorApp extends StatelessWidget {
  const VendorApp({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Vendor studio',
          theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff8c4a22))),
          home: !store.live
              ? VendorPage(store: store)
              : store.user == null
                  ? VendorLoginPage(store: store)
                  : VendorPage(store: store),
        ),
      );
}

class VendorLoginPage extends StatefulWidget {
  const VendorLoginPage({super.key, required this.store});
  final Store store;
  @override
  State<VendorLoginPage> createState() => _VendorLoginPageState();
}

class _VendorLoginPageState extends State<VendorLoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await widget.store.login(email.text.trim(), password.text);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vendor studio')),
        body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Sign in with the account used for your shop application.'),
            const SizedBox(height: 20),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email address')),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true, onSubmitted: (_) => submit(), decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 20),
            FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Signing in...' : 'Sign in')),
          ]),
        ))),
      );
}
