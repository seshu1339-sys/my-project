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
import 'ui/app_bottom_ad.dart';
import 'ui/sign_in_panel.dart';
import 'ui/vendor_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // App errors and start speed for the admin's Setup check (lib/services/app_monitoring.dart).
  AppMonitoring.start(app: 'vendor');
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
  store.appRole = 'vendor';
  await store.init();
  // Usage analytics (lib/services/usage.dart): only with Firebase connected.
  if (live) {
    unawaited(startUsage(app: 'vendor'));
    // Views of the ads in the bottom box (lib/ui/app_bottom_ad.dart).
    unawaited(Analytics.startAppAdTracker());
    // Google Analytics on the website (lib/services/google_analytics.dart), when the build has the measurement id.
    startGoogleAnalytics(app: 'vendor');
  }
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
          // The ads box at the bottom of every page, once signed in.
          builder: (context, child) => withAppBottomAd(context, child, store),
          // After sign-in: the home with Vendor, Services and Transport (ui/vendor_home.dart).
          home: !store.live
              ? VendorHomePage(store: store)
              : store.user == null
                  ? VendorLoginPage(store: store)
                  : VendorHomePage(store: store),
        ),
      );
}

/// Vendors and service providers sign in with Google (or an emailed code); the registration form opens once the email is in.
class VendorLoginPage extends StatelessWidget {
  const VendorLoginPage({super.key, required this.store});
  final Store store;

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
                const Text('Sign in with your Google account. Once you are in you can register your shop or service for approval.'),
                const SizedBox(height: 16),
                SignInPanel(store: store),
              ]),
            ),
          ),
        ),
      );
}
