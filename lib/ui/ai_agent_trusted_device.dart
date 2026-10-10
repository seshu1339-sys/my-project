import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/store.dart';
import 'ai_agent_confirmation.dart';

/// "Registered trusted Admin iPhone" — honestly, a persistent-token gate
/// (like a long-lived cookie stored via shared_preferences, which on Flutter
/// Web is backed by localStorage), not hardware attestation. It scopes WHO
/// even reaches the WebAuthn/Face ID step that follows it in the gatekeeper;
/// the real cryptographic boundary is that step. Clearing Safari site data
/// invalidates this token, requiring OTP-gated re-registration. Removing this
/// file denies protected access (fails closed).
const _tokenPrefsKey = 'aiAgentTrustedDeviceToken';

Future<bool> hasRegisteredTrustedDevice() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_tokenPrefsKey) != null;
}

Future<bool> verifyThisDeviceIsTrusted(Store store) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(_tokenPrefsKey);
  if (token == null) return false;
  try {
    await store.call('verifyTrustedDevice', {'token': token});
    return true;
  } catch (_) {
    return false;
  }
}

/// Registers the CURRENT device as the one trusted Admin device, gated
/// behind a fresh OTP round as strong proof. Overwrites any previously
/// registered device (there is only ever one trusted device at a time, per
/// the spec's singular "the registered trusted Admin iPhone").
Future<bool> registerThisDeviceAsTrusted(BuildContext context, Store store) async {
  final verified = await ensureFreshOtp(context, store, 'Register this device as the trusted Admin iPhone.');
  if (!verified) return false;
  try {
    final result = await store.call('registerTrustedDevice', {'label': 'iPhone'});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenPrefsKey, result['token'] as String);
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}

/// A plain button for AiAgentSettings — registering is rare enough (once per
/// device) that it doesn't need its own dedicated page. [onRegistered] is
/// called right after a successful registration (e.g. the gatekeeper uses it
/// to advance to its next step automatically, instead of leaving the admin
/// stuck on this screen until they notice a separate "try again" button).
class RegisterTrustedDeviceButton extends StatelessWidget {
  const RegisterTrustedDeviceButton({super.key, required this.store, this.onRegistered});
  final Store store;
  final VoidCallback? onRegistered;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    icon: const Icon(Icons.phone_iphone),
    label: const Text('Register this device as the trusted Admin iPhone'),
    onPressed: () async {
      final ok = await registerThisDeviceAsTrusted(context, store);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'This device is now trusted.' : 'Registration was not completed.')));
      }
      if (ok) onRegistered?.call();
    },
  );
}
