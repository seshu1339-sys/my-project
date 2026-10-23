import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/strings.dart';

import '../data/store.dart';
import 'account_language_field.dart';
import 'email_link.dart';
import 'layout_settings.dart';
import 'page_widgets.dart';
import 'shared.dart';

/// Throws if [value] isn't a plausible email address. Shared by this form
/// and AccountPage's own "Reset password by email" button for an
/// already-authenticated user.
void validateEmailAddress(String value) {
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
    throw StateError('Enter a valid email address.');
  }
}

/// Sends a password-reset email to [currentUserEmail] if signed in, else to
/// [typedEmail] after validating it. Shared by the same two call sites;
/// doesn't show any message itself so each caller's own `run()` wrapper
/// controls that exactly as before.
Future<void> sendPasswordReset(
  Store store, {
  required String? currentUserEmail,
  required String typedEmail,
}) async {
  final address = currentUserEmail ?? typedEmail.trim();
  if (currentUserEmail == null) validateEmailAddress(typedEmail);
  await store.resetPassword(address);
}

/// The signed-out "Welcome to your neighbourhood" / "Create your account"
/// form: language picker, email+password sign-in/register, email-link
/// sign-in, forgot-password. Fully self-contained -- owns its own
/// controllers and busy/registering state -- since it only ever renders
/// when store.user is null, with no state to share with AccountPage's other
/// (signed-in) branches. Extracted out of account.dart so the account shell
/// stays a thin composition root; behavior is unchanged from the original
/// inline version.
class AccountAuthForm extends StatefulWidget {
  const AccountAuthForm({super.key, required this.store});
  final Store store;
  @override
  State<AccountAuthForm> createState() => _AccountAuthFormState();
}

class _AccountAuthFormState extends State<AccountAuthForm> {
  final email = TextEditingController(),
      password = TextEditingController(),
      confirmPassword = TextEditingController();
  bool registering = false, busy = false;

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        message(
          context,
          e.message ?? 'Authentication failed. Please try again.',
        );
      }
    } catch (e) {
      if (mounted) {
        message(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      registering
          ? Text(
              'Create your account'.tr(context),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            )
          : pageHeadingText(
              context,
              layout: layoutFor(context, widget.store.entries('settings'), 'authFormHeading'),
              defaultText: 'Welcome to your neighbourhood',
              fontSize: 28,
            ),
      const SizedBox(height: 12),
      Text(
        registering
            ? 'Register with email and password, then verify your email.'.tr(context)
            : 'Sign in with your email and password.'.tr(context),
      ),
      const SizedBox(height: 24),
      AccountLanguageField(
        store: widget.store,
        onChanged: (value) => run(() => widget.store.setLanguage(value)),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: email,
        enabled: !busy,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        autocorrect: false,
        decoration: InputDecoration(labelText: 'Email address'.tr(context)),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: password,
        enabled: !busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [
          registering ? AutofillHints.newPassword : AutofillHints.password,
        ],
        decoration: InputDecoration(labelText: 'Password'.tr(context)),
      ),
      OutlinedButton(
        onPressed: busy
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EmailLinkPage(store: widget.store),
                ),
              ),
        child: Text('Sign in with an email link'.tr(context)),
      ),
      if (registering) ...[
        const SizedBox(height: 14),
        TextField(
          controller: confirmPassword,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: 'Confirm password'.tr(context)),
        ),
      ],
      FilledButton(
        onPressed: busy
            ? null
            : () => run(() async {
                validateEmailAddress(email.text);
                if (password.text.isEmpty) {
                  throw StateError('Enter your password.'.tr(context));
                }
                if (registering) {
                  if (password.text.length < 6) {
                    throw StateError(
                      'Use at least six characters for your password.'.tr(context),
                    );
                  }
                  if (password.text != confirmPassword.text) {
                    throw StateError('Passwords do not match.'.tr(context));
                  }
                  await widget.store.registerEmail(
                    email.text.trim(),
                    password.text,
                  );
                  // Registration is done; the sign-in form must be what shows after a later logout.
                  if (mounted) setState(() => registering = false);
                } else {
                  await widget.store.login(email.text.trim(), password.text);
                }
                password.clear();
                confirmPassword.clear();
              }),
        child: Text(registering ? 'Create account'.tr(context) : 'Sign in'.tr(context)),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => setState(() {
                registering = !registering;
                password.clear();
                confirmPassword.clear();
              }),
        child: Text(registering ? 'Back to sign in'.tr(context) : 'Create an account'.tr(context)),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => run(() async {
                await sendPasswordReset(
                  widget.store,
                  currentUserEmail: null,
                  typedEmail: email.text,
                );
                if (context.mounted) {
                  message(context, 'If an account exists, a password reset email has been sent.'.tr(context));
                }
              }),
        child: Text('Forgot password?'.tr(context)),
      ),
      if (busy) const LinearProgressIndicator(),
    ],
  );
}
