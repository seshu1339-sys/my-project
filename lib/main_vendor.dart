import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'data/store.dart';
import 'services/firebase_startup.dart';
import 'services/emulators.dart';
import 'ui/email_link.dart';
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

/// On the web the emailed link returns to this same vendor site; on Android the
/// vendor pastes the link into the app (the same fallback the customer app has).
String? get vendorContinueUrl => kIsWeb ? '${Uri.base.origin}/?emailSignIn=1' : null;

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
              : store.pendingEmailLink != null
                  ? EmailLinkPage(store: store, continueUrl: vendorContinueUrl)
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
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vendor studio')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Become a vendor', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('Enter your email to receive a secure sign-in link. Once your email is verified you can register your shop for approval.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => EmailLinkPage(store: widget.store, continueUrl: vendorContinueUrl))),
                  child: const Text('Continue with email link'),
                ),
                const SizedBox(height: 28),
                const Text('Returning vendor? Sign in with your password.'),
                const SizedBox(height: 8),
                TextField(controller: email, decoration: const InputDecoration(labelText: 'Email address')),
                const SizedBox(height: 12),
                TextField(controller: password, obscureText: true, onSubmitted: (_) => submit(), decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: busy ? null : submit, child: Text(busy ? 'Signing in...' : 'Sign in')),
              ]),
            ),
          ),
        ),
      );
}
