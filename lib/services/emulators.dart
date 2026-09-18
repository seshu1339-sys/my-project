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
///
/// bool.fromEnvironment/String.fromEnvironment only fold to their dart-define
/// value in a genuine compile-time constant context; on some backends
/// (confirmed: Android AOT) calling them directly inside a runtime `if`
/// silently evaluates to their default instead of throwing, so every flag
/// here is read into its own top-level const first.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS');
const _emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: 'localhost',
);

Future<void> connectToEmulatorsIfConfigured() async {
  if (!_useEmulators) return;
  FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
  await FirebaseStorage.instance.useStorageEmulator(_emulatorHost, 9199);
  FirebaseFunctions.instance.useFunctionsEmulator(_emulatorHost, 5001);
}
