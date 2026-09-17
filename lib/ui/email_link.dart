import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import 'shared.dart';

class EmailLinkPage extends StatefulWidget {
  const EmailLinkPage({super.key, required this.store});
  final Store store;
  @override
  State<EmailLinkPage> createState() => _EmailLinkPageState();
}

class _EmailLinkPageState extends State<EmailLinkPage> {
  late final email = TextEditingController(
    text: widget.store.emailForSignInLink,
  );
  late final link = TextEditingController(
    text: widget.store.pendingEmailLink ?? '',
  );
  late bool completing = widget.store.pendingEmailLink != null;
  bool busy = false, sent = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final address = email.text.trim();
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
        throw StateError(
          'Enter the email address that should receive the link.',
        );
      }
      if (completing) {
        await widget.store.completeSignInLink(address, link.text.trim());
        await SystemNavigator.routeInformationUpdated(
          uri: Uri(path: '/'),
          replace: true,
        );
        if (mounted) {
          message(context, 'Signed in with your verified email');
          if (Navigator.canPop(context)) Navigator.pop(context);
        }
      } else {
        await widget.store.sendSignInLink(address);
        if (mounted) setState(() => sent = true);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => error =
              [
                'invalid-action-code',
                'expired-action-code',
                'invalid-credential',
              ].contains(e.code)
              ? 'This link is invalid, expired, or already used. Request a new sign-in link.'
              : e.message ?? 'Sign-in could not finish. Please try again.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Email link sign-in')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              completing
                  ? 'Confirm your email to sign in'
                  : 'Sign in without a password',
              style: const TextStyle(fontSize: 26),
            ),
            const SizedBox(height: 12),
            Text(
              completing
                  ? 'Use the same email address that received this link. On another device, enter it again.'
                  : 'We will email you a secure sign-in link. Opening it also verifies your email.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            if (completing) ...[
              const SizedBox(height: 14),
              TextField(
                controller: link,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Sign-in link',
                  helperText:
                      'Paste the full link if you opened it on another device.',
                ),
              ),
            ],
            if (sent)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Sign-in link sent. Check your inbox and spam folder.',
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(
                completing
                    ? 'Complete sign-in'
                    : sent
                    ? 'Send another sign-in link'
                    : 'Send sign-in link',
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      completing = !completing;
                      error = null;
                      sent = false;
                    }),
              child: Text(
                completing
                    ? 'Request a new link'
                    : 'I already have a sign-in link',
              ),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}
