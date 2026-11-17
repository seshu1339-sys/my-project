import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/store.dart';
import '../services/strings.dart';
import 'consent_checkbox.dart';
import 'policy_links.dart';

/// The one sign-in used by the customer, vendor and staff apps and the website: "Continue with Google" (the Google account already on
/// the phone, its email shown, one tap, no typing) and, only when Google did not work, is not possible or was closed, a 6-digit code
/// emailed to the person (the field starts with the last email used on this phone). Both prove the email; the app then signs in with
/// that email's own account for this app's role (Store.enterAppRole, functions/role-logins.js), made on the first sign-in, so signing
/// in and registering are one step. The same email may have an account in every app, each separate.
///
/// With [opensGoogle], the Google sheet (on the website the One Tap prompt) opens by itself as soon as the panel shows, once per run of
/// the app and never right after Log out ([Store.opensGoogleByItself]). Above the button: "By continuing, you agree to ..." (no tick).
class SignInPanel extends StatefulWidget {
  const SignInPanel({super.key, required this.store, this.opensGoogle = true});
  final Store store;
  final bool opensGoogle;
  @override
  State<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<SignInPanel> {
  final email = TextEditingController(), code = TextEditingController();
  bool busy = false, emailOpen = false, sent = false;
  String? error;

  @override
  void initState() {
    super.initState();
    email.text = widget.store.lastSignInEmail;
    if (widget.opensGoogle && widget.store.opensGoogleByItself) {
      widget.store.googleOpenedByItself();
      // After the first frame, so the screen (and its agreement sentence) is already there under Google's sheet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _google(automatic: true);
      });
    }
  }

  /// Continuing under the agreement sentence is the agreement (saved right after sign-in).
  void _agree() {
    if (widget.store.asksConsentBeforeSignIn) widget.store.pendingConsent = true;
  }

  /// "Continue with Google" (or, [automatic], the sheet opening by itself). The email code is offered once Google is closed without
  /// choosing an account, or does not work.
  Future<void> _google({bool automatic = false}) async {
    var worked = false;
    await run(() async {
      _agree();
      final result = await widget.store.signInWithGoogle(automatic: automatic);
      worked = true;
      if (result == false) widget.store.offerEmailCode();
    });
    if (!worked) widget.store.offerEmailCode();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on StateError catch (e) {
      if (mounted) setState(() => error = e.message);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Something went wrong. Please try again.'.tr(context));
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = e.message ?? 'Sign-in failed. Please try again.'.tr(context));
    } on GoogleSignInException catch (e) {
      // The code (for example clientConfigurationError) tells support what to fix; the words stay the same for everyone.
      if (mounted) setState(() => error = '${'Google sign-in did not work. Please try again, or use an email code.'.tr(context)} (${e.code.name})');
    } catch (e) {
      if (mounted) setState(() => error = 'Google sign-in did not work. Please try again, or use an email code.'.tr(context));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _checkEmail() {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      throw StateError('Enter a valid email address.'.tr(context));
    }
  }

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final shown = error ?? widget.store.roleBlock;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Agreement to the Terms and the Privacy Policy comes with signing up (and so with signing in, as a new account is made by
          // the same buttons): continuing under this sentence agrees. Once an agreement is saved on this phone it is not shown again.
          if (widget.store.asksConsentBeforeSignIn) ConsentNotice(store: widget.store),
          FilledButton.icon(
            key: const ValueKey('google-sign-in'),
            onPressed: busy ? null : () => _google(),
            icon: const Icon(Icons.account_circle_outlined),
            label: Text('Continue with Google'.tr(context)),
          ),
          if (shown != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                shown,
                key: const ValueKey('sign-in-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          // The email code only once Google did not work, is not possible here, or was closed (Store.emailCodeOffered).
          if (widget.store.emailCodeOffered) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('email-code-toggle'),
            onPressed: busy ? null : () => setState(() => emailOpen = !emailOpen),
            child: Text(
              emailOpen ? 'Hide the email code option'.tr(context) : 'Google did not work? Use an email code'.tr(context),
            ),
          ),
          if (emailOpen) ...[
            TextField(
              key: const ValueKey('code-email'),
              controller: email,
              enabled: !busy && !sent,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: 'Email address'.tr(context)),
            ),
            const SizedBox(height: 12),
            if (!sent)
              OutlinedButton(
                key: const ValueKey('send-code'),
                onPressed: busy
                    ? null
                    : () => run(() async {
                        _checkEmail();
                        _agree();
                        await widget.store.requestEmailCode(email.text.trim());
                        if (mounted) setState(() => sent = true);
                      }),
                child: Text('Send me a code'.tr(context)),
              )
            else ...[
              Text('We sent a 6-digit code to the email address. Check your inbox and spam folder.'.tr(context)),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('code-field'),
                controller: code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(labelText: '6-digit code'.tr(context)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('verify-code'),
                onPressed: busy
                    ? null
                    : () => run(() async {
                        if (code.text.length != 6) throw StateError('Enter the 6-digit code.'.tr(context));
                        await widget.store.verifyEmailCode(email.text.trim(), code.text);
                        code.clear();
                      }),
                child: Text('Verify and sign in'.tr(context)),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        sent = false;
                        code.clear();
                        error = null;
                      }),
                child: Text('Use a different email or send a new code'.tr(context)),
              ),
            ],
          ],
          ],
          if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          // Privacy, terms and contact pages (lib/ui/policy_links.dart): required for the store listings and the payment gateway.
          PolicyLinks(appRole: widget.store.appRole),
        ],
      );
    },
  );
}
