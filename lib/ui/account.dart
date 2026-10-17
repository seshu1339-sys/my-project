import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/store.dart';
import 'shared.dart';
import 'account_auth_form.dart';
import 'account_complaint_dialog.dart' as complaint_dialog;
import 'account_complaints_section.dart';
import 'account_language_field.dart';
import 'account_orders_section.dart';
import 'account_payment_card_section.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.store});
  final Store store;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final name = TextEditingController();
  bool busy = false;
  final cardBrand = TextEditingController(),
      cardLast4 = TextEditingController();
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
  void initState() {
    super.initState();
    name.text = widget.store.profileName;
    cardBrand.text = widget.store.paymentBrand;
    cardLast4.text = widget.store.paymentLast4;
  }

  @override
  void dispose() {
    name.dispose();
    cardBrand.dispose();
    cardLast4.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your account')),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!widget.store.live) ...[
                const Icon(Icons.person_outline, size: 64),
                const SizedBox(height: 20),
                const Text(
                  'You’re exploring the demo',
                  style: TextStyle(fontSize: 26),
                ),
                const Text(
                  'Email sign-in and orders become available when Firebase is connected. Browse products and try the cart freely.',
                ),
              ] else if (widget.store.user != null &&
                  !widget.store.user!.emailVerified) ...[
                const Text('Verify your email', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 12),
                Text(
                  'Open the verification link sent to ${widget.store.user!.email ?? 'your email'}, then return here. Check your spam folder too.',
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final verified = await widget.store
                              .refreshEmailVerification();
                          if (context.mounted && !verified) {
                            message(
                              context,
                              'Your email is not verified yet. Open the email link first.',
                            );
                          }
                        }),
                  child: const Text('I have verified my email'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await widget.store.sendVerificationEmail();
                          if (context.mounted) {
                            message(context, 'Verification email sent');
                          }
                        }),
                  child: const Text('Resend verification email'),
                ),
                TextButton(
                  onPressed: busy ? null : () => run(widget.store.logout),
                  child: const Text('Log out / Use another email'),
                ),
              ] else if (widget.store.user != null) ...[
                Text(
                  widget.store.user!.email ?? 'Your profile',
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await widget.store.updateProfile(name.text.trim());
                          if (context.mounted) {
                            message(context, 'Profile saved');
                          }
                        }),
                  child: const Text('Save profile'),
                ),
                const SizedBox(height: 20),
                AccountLanguageField(
                  store: widget.store,
                  onChanged: (value) =>
                      run(() => widget.store.setLanguage(value)),
                ),
                const SizedBox(height: 14),
                AccountPaymentCardSection(
                  store: widget.store,
                  busy: busy,
                  run: run,
                  cardBrand: cardBrand,
                  cardLast4: cardLast4,
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await sendPasswordReset(
                            widget.store,
                            currentUserEmail: widget.store.user?.email,
                            typedEmail: '',
                          );
                          if (context.mounted) {
                            message(
                              context,
                              'If an account exists, a password reset email has been sent.',
                            );
                          }
                        }),
                  child: const Text('Reset password by email'),
                ),
                TextButton(
                  onPressed: () => run(widget.store.logout),
                  child: const Text('Log out'),
                ),
                const Divider(),
                const Text(
                  'Get price-drop alerts for items you view and new offer notifications. Your signed-in item views are saved privately to personalize these alerts.',
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await widget.store.notifications.enable(
                            pincode: widget.store.pincode,
                            latitude: widget.store.latitude,
                            longitude: widget.store.longitude,
                          );
                          if (context.mounted) {
                            message(
                              context,
                              'Price-drop and offer alerts enabled',
                            );
                          }
                        }),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Enable alerts on this device'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await widget.store.notifications.disable();
                          if (context.mounted) {
                            message(context, 'Alerts disabled');
                          }
                        }),
                  child: const Text('Disable alerts for my account'),
                ),
                const Text('Your orders', style: TextStyle(fontSize: 22)),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => complaint_dialog.showComplaintDialog(
                          context,
                          widget.store,
                          run,
                        ),
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text('Open a complaint'),
                ),
                AccountComplaintsSection(store: widget.store),
                AccountOrdersSection(store: widget.store, run: run),
              ] else
                AccountAuthForm(store: widget.store),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}
