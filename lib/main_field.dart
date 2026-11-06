import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'data/store.dart';
import 'services/firebase_startup.dart';
import 'services/analytics.dart';
import 'services/usage_start.dart';
import 'services/app_monitoring.dart';
import 'services/google_analytics.dart';
import 'services/emulators.dart';
import 'services/server_clock.dart';
import 'ui/app_bottom_ad.dart';
import 'ui/consent_checkbox.dart';
import 'ui/sign_in_panel.dart';
import 'ui/field.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ads and offers start and end by the server's clock, not the phone's (lib/services/server_clock.dart). Never blocks the start.
  unawaited(ServerClock.start());
  // App errors and start speed for the admin's Setup check (lib/services/app_monitoring.dart).
  AppMonitoring.start(app: 'staff');
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
  store.appRole = 'staff';
  store.requiresConsent = true;
  await store.init();
  // Usage analytics (lib/services/usage.dart): only with Firebase connected.
  if (live) {
    unawaited(startUsage(app: 'staff'));
    // Views of the ads in the bottom box (lib/ui/app_bottom_ad.dart).
    unawaited(Analytics.startAppAdTracker());
    // Google Analytics on the website (lib/services/google_analytics.dart), when the build has the measurement id.
    startGoogleAnalytics(app: 'staff');
  }
  runApp(FieldAssistantApp(store: store));
}

class FieldAssistantApp extends StatelessWidget {
  const FieldAssistantApp({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Loca Market staff',
          theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1b5e20))),
          // The ads box at the bottom of every page, once signed in.
          builder: (context, child) => withConsentGate(context, withAppBottomAd(context, child, store, staff: true), store),
          home: !store.live
              ? const FieldDemoPage()
              : store.user == null
                  ? FieldLoginPage(store: store)
                  : FieldHomePage(store: store),
        ),
      );
}

class FieldDemoPage extends StatelessWidget {
  const FieldDemoPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Loca Market staff')),
        body: const Center(child: Text('Connect Firebase to sign in and submit field entries.')),
      );
}

/// Staff sign in with Google (or an emailed code); an administrator must then approve the access before anything can be submitted.
class FieldLoginPage extends StatelessWidget {
  const FieldLoginPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Loca Market staff')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Staff sign-in', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('Sign in with your Google account. After you register, an administrator must approve your access before you can submit anything.'),
                const SizedBox(height: 16),
                SignInPanel(store: store),
              ]),
            ),
          ),
        ),
      );
}
