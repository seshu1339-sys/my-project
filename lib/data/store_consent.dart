import 'package:shared_preferences/shared_preferences.dart';

import '../domain/consent.dart';
import 'store.dart';

/// Agreement to the Terms & Conditions and the Privacy Policy, kept on the server (functions/consent.js): who, when, which version.
///
/// A person ticks the box before signing up (the sign-in screen, [Store.pendingConsent]); the agreement is saved right after sign-in.
/// Anyone signed in without a saved agreement for the current version (an account made before this existed, or a new version of the
/// pages) sees the agreement screen once ([Store.consentNeeded]). After that nobody is asked again, on login or later, until
/// [policyVersion] changes. The customer, vendor and staff apps use it; the admin app does not ([Store.requiresConsent]).
extension StoreConsent on Store {
  static const _deviceKey = 'consent_device';
  static String _uidKey(String uid) => 'consent_uid_$uid';

  /// Reads what this phone remembers; called when the store starts.
  Future<void> loadConsentDevice() async {
    final prefs = await SharedPreferences.getInstance();
    deviceConsented = prefs.getString(_deviceKey) == policyVersion;
  }

  String get _consentApp => switch (appRole) {
    'vendor' => 'vendor',
    'staff' => 'staff',
    _ => 'customer',
  };

  Future<void> _rememberConsent(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uidKey(uid), policyVersion);
    await prefs.setString(_deviceKey, policyVersion);
    deviceConsented = true;
    pendingConsent = false;
    consentNeeded = false;
  }

  /// Works out, right after a verified sign-in, whether this person has agreed to the current version.
  /// A network failure never locks anyone out; it is checked again the next time.
  Future<void> syncConsent() async {
    final current = user;
    if (!live || !requiresConsent || current == null || !emailConfirmed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_uidKey(current.uid)) == policyVersion) {
        consentNeeded = false;
        return;
      }
      if (pendingConsent) {
        await _record(current.uid);
        return;
      }
      final status = await call('consentStatus', {});
      if (status['accepted'] == true) {
        await _rememberConsent(current.uid);
      } else {
        consentNeeded = true;
      }
    } catch (_) {
      // A person who ticked but whose agreement could not be saved sees the agreement screen, which can try again. Anyone else
      // is not blocked by a failed check.
      if (pendingConsent) consentNeeded = true;
    } finally {
      consentChanged();
    }
  }

  Future<void> _record(String uid) async {
    await call('recordConsent', {'app': _consentApp, 'version': policyVersion});
    await _rememberConsent(uid);
  }

  /// The "Agree and continue" button of the agreement screen. Throws when the agreement could not be saved.
  Future<void> acceptConsent() async {
    final current = user;
    if (current == null) throw StateError('Sign in first.');
    await _record(current.uid);
    consentChanged();
  }
}
