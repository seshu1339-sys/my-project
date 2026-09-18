import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Local development/testing only. Off by default in every real build —
/// production Firebase is untouched unless USE_EMULATORS=true is passed
/// explicitly at build time, alongside a non-production FIREBASE_PROJECT_ID
/// (e.g. a "demo-*" project id matching `firebase emulators:start`).
///
/// EMULATOR_HOST defaults to localhost; Android emulators must override it
/// to 10.0.2.2, which is the emulator's alias for the host machine's
/// loopback address, not a real address to route to over a network.
Future<void> connectToEmulatorsIfConfigured() async {
  if (!bool.fromEnvironment('USE_EMULATORS')) return;
  const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
}
