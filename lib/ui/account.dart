import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'shared.dart';
import 'account_complaints_section.dart';
import 'account_language_field.dart';
import 'account_orders_section.dart';
import 'account_payment_card_section.dart';
import 'email_link.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.store});
  final Store store;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final email = TextEditingController(),
      password = TextEditingController(),
      confirmPassword = TextEditingController(),
      name = TextEditingController();
  bool registering = false, busy = false;
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

  Future<void> showComplaintDialog() async {
    // The server requires a complaint to reference an order, so the customer picks one.
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs;
    try {
      orderDocs = (await FirebaseFirestore.instance.collection('orders').where('userId', isEqualTo: widget.store.user!.uid).limit(30).get()).docs;
    } catch (_) {
      if (mounted) message(context, 'Your orders could not load. Please try again.');
      return;
    }
    if (orderDocs.isEmpty) {
      if (mounted) message(context, 'Place an order first, then you can open a complaint about it.');
      return;
    }
    var orderId = orderDocs.first.id;
    if (!mounted) return;
    final subject = TextEditingController(), description = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open a complaint'),
        content: SingleChildScrollView(child: Column(children: [
          DropdownButtonFormField<String>(
            initialValue: orderId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Order'),
            items: [for (final order in orderDocs) DropdownMenuItem(value: order.id, child: Text('Order ${order.id.substring(0, 8)} • ${order.data()['status'] ?? ''}', overflow: TextOverflow.ellipsis))],
            onChanged: (value) { if (value != null) orderId = value; },
          ),
          TextField(controller: subject, decoration: const InputDecoration(labelText: 'Subject')),
          TextField(controller: description, maxLines: 5, decoration: const InputDecoration(labelText: 'What happened?')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit'))],
      ),
    );
    if (submit != true) { subject.dispose(); description.dispose(); return; }
    await run(() async {
      await widget.store.createComplaint(orderId: orderId, subject: subject.text, description: description.text);
      if (mounted) message(context, 'Complaint submitted. You can follow its full history here.');
    });
    subject.dispose(); description.dispose();
  }

  void validateEmail() {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      throw StateError('Enter a valid email address.');
    }
  }

  Future<void> resetPassword() async {
    final address = widget.store.user?.email ?? email.text.trim();
    if (widget.store.user == null) validateEmail();
    await widget.store.resetPassword(address);
    if (mounted) {
      message(
        context,
        'If an account exists, a password reset email has been sent.',
      );
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
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
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
                  onChanged: (value) => run(() => widget.store.setLanguage(value)),
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
                  onPressed: busy ? null : () => run(resetPassword),
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
                OutlinedButton.icon(onPressed: busy ? null : showComplaintDialog, icon: const Icon(Icons.report_problem_outlined), label: const Text('Open a complaint')),
                AccountComplaintsSection(store: widget.store),
                AccountOrdersSection(store: widget.store, run: run),
              ] else ...[
                Text(
                  registering
                      ? 'Create your account'
                      : 'Welcome to your neighbourhood',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  registering
                      ? 'Register with email and password, then verify your email.'
                      : 'Sign in with your email and password.',
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
                  decoration: const InputDecoration(labelText: 'Email address'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: [
                    registering
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: const InputDecoration(labelText: 'Password'),
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
                  child: const Text('Sign in with an email link'),
                ),
                if (registering) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: confirmPassword,
                    enabled: !busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                    ),
                  ),
                ],
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          validateEmail();
                          if (password.text.isEmpty) {
                            throw StateError('Enter your password.');
                          }
                          if (registering) {
                            if (password.text.length < 6) {
                              throw StateError(
                                'Use at least six characters for your password.',
                              );
                            }
                            if (password.text != confirmPassword.text) {
                              throw StateError('Passwords do not match.');
                            }
                            await widget.store.registerEmail(
                              email.text.trim(),
                              password.text,
                            );
                            // Registration is done; the sign-in form must be what shows after a later logout.
                            if (mounted) setState(() => registering = false);
                          } else {
                            await widget.store.login(
                              email.text.trim(),
                              password.text,
                            );
                          }
                          password.clear();
                          confirmPassword.clear();
                        }),
                  child: Text(registering ? 'Create account' : 'Sign in'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          registering = !registering;
                          password.clear();
                          confirmPassword.clear();
                        }),
                  child: Text(
                    registering ? 'Back to sign in' : 'Create an account',
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => run(resetPassword),
                  child: const Text('Forgot password?'),
                ),
              ],
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}
