import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../services/strings.dart';
import 'policy_links.dart';

/// The one sign-in used by the customer, vendor and staff apps: "Continue with Google" (the phone's own account list, one tap, no
/// typing) and, as a backup for people with no Google account, a 6-digit code emailed to them. Both end with a verified email; the
/// app's own gate (Store.appRole, functions/login.js) then decides whether that email may come in.
class SignInPanel extends StatefulWidget {
  const SignInPanel({super.key, required this.store});
  final Store store;
  @override
  State<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<SignInPanel> {
  final email = TextEditingController(), code = TextEditingController();
  bool busy = false, emailOpen = false, sent = false;
  String? error;

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
          FilledButton.icon(
            key: const ValueKey('google-sign-in'),
            onPressed: busy ? null : () => run(widget.store.signInWithGoogle),
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
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('email-code-toggle'),
            onPressed: busy ? null : () => setState(() => emailOpen = !emailOpen),
            child: Text(
              emailOpen ? 'Hide the email code option'.tr(context) : 'No Google account? Use an email code'.tr(context),
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
          if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          // Privacy, terms and contact pages (lib/ui/policy_links.dart): required for the store listings and the payment gateway.
          PolicyLinks(appRole: widget.store.appRole),
        ],
      );
    },
  );
}
