import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'data/store.dart';
import 'ui/storefront.dart';
import 'ui/details.dart';
import 'domain/catalog.dart';

final _navigator = GlobalKey<NavigatorState>();
final _messenger = GlobalKey<ScaffoldMessengerState>();

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
  final firestore = live ? FirebaseFirestore.instance : null;
  final store = Store(live: live, database: firestore);
  await store.init();
  runApp(MarketApp(store: store));
  if (live) {
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null) {
        _messenger.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              '${notification.title ?? 'New alert'}: ${notification.body ?? ''}',
            ),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openAlert(store, message),
            ),
          ),
        );
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _openAlert(store, message),
    );
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        await WidgetsBinding.instance.endOfFrame;
        await _openAlert(store, message);
      }
    } catch (_) {
      /* Unsupported messaging must not block the storefront. */
    }
  }
}

Future<void> _openAlert(Store store, RemoteMessage message) async {
  final id = message.data['productId'];
  if (id == null) {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    return;
  }
  try {
    final doc = await store.firestore.collection('products').doc(id).get();
    if (doc.exists) {
      _navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductPage(store: store, entry: Entry(doc.id, doc.data()!)),
        ),
      );
    }
  } catch (_) {
    _messenger.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Could not open this item. Please try searching for it.'),
      ),
    );
  }
}

class MarketApp extends StatelessWidget {
  const MarketApp({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    scaffoldMessengerKey: _messenger,
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
