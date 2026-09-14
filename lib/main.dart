import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'data/store.dart';
import 'ui/storefront.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
  var live = false;
  String? startupError;
  if (project.isNotEmpty) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
          appId: String.fromEnvironment('FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment(
            'FIREBASE_MESSAGING_SENDER_ID',
          ),
          projectId: project,
          authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
          storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
          iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
        ),
      );
      live = true;
    } catch (e) {
      startupError = 'Firebase could not start. Check the supplied project configuration and restart.';
    }
  }
  if (startupError != null) {
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(startupError))),
      ),
    );
    return;
  }
  final store = Store(live: live);
  await store.init();
  runApp(MarketApp(store: store));
}

class MarketApp extends StatelessWidget {
  const MarketApp({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Neighbourly • Your local marketplace',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b50)),
      scaffoldBackgroundColor: const Color(0xfff7f8f4),
      fontFamily: 'Arial',
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(elevation: 0, color: Colors.white),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff7f8f4),
        surfaceTintColor: Colors.transparent,
      ),
    ),
    home: Storefront(store: store),
  );
}
