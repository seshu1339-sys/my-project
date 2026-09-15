import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const firebaseOptions = FirebaseOptions(
  apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
  appId: String.fromEnvironment('FIREBASE_APP_ID'),
  messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
  projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
  storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
  iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
);

/// Android invokes this top-level entry point in a separate isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  // FCM displays notification payloads itself. Do not navigate or display a
  // second notification here. Keep future data-only processing short and async.
  if (kDebugMode) {
    debugPrint('Received a Firebase background message.');
  }
}
