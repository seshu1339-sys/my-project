import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/strings.dart';

import '../data/store.dart';
import 'shared.dart';

class EmailLinkPage extends StatefulWidget {
  const EmailLinkPage({super.key, required this.store, this.continueUrl});
  final Store store;
  final String? continueUrl;
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
          'Enter the email address that should receive the link.'.tr(context),
        );
      }
      if (completing) {
        await widget.store.completeSignInLink(address, link.text.trim());
        await SystemNavigator.routeInformationUpdated(
          uri: Uri(path: '/'),
          replace: true,
        );
        if (mounted) {
          message(context, 'Signed in with your verified email'.tr(context));
          if (Navigator.canPop(context)) Navigator.pop(context);
        }
      } else {
        await widget.store.sendSignInLink(address, continueUrl: widget.continueUrl);
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
              ? 'This link is invalid, expired, or already used. Request a new sign-in link.'.tr(context)
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
    appBar: AppBar(title: Text('Email link sign-in'.tr(context))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              completing
                  ? 'Confirm your email to sign in'.tr(context)
                  : 'Sign in without a password'.tr(context),
              style: const TextStyle(fontSize: 26),
            ),
            const SizedBox(height: 12),
            Text(
              completing
                  ? 'Use the same email address that received this link. On another device, enter it again.'.tr(context)
                  : 'We will email you a secure sign-in link. Opening it also verifies your email.'.tr(context),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: 'Email address'.tr(context)),
            ),
            if (completing) ...[
              const SizedBox(height: 14),
              TextField(
                controller: link,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Sign-in link'.tr(context),
                  helperText:
                      'Paste the full link if you opened it on another device.'.tr(context),
                ),
              ),
            ],
            if (sent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Sign-in link sent. Check your inbox and spam folder.'.tr(context),
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
                    ? 'Complete sign-in'.tr(context)
                    : sent
                    ? 'Send another sign-in link'.tr(context)
                    : 'Send sign-in link'.tr(context),
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
                    ? 'Request a new link'.tr(context)
                    : 'I already have a sign-in link'.tr(context),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}
