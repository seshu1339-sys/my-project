import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../services/localization.dart';
import 'shared.dart';
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
                DropdownButtonFormField<String>(
                  initialValue:
                      AppLocale.names.containsKey(widget.store.language)
                      ? widget.store.language
                      : 'en',
                  decoration: const InputDecoration(
                    labelText: 'Language / भाषा',
                  ),
                  items: AppLocale.names.entries
                      .where(
                        (entry) => AppLocale.enabled(
                          widget.store.business.text('enabledLanguages'),
                        ).any((locale) => locale.languageCode == entry.key),
                      )
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) run(() => widget.store.setLanguage(value));
                  },
                ),
                const SizedBox(height: 14),
                const Text('Payment card', style: TextStyle(fontSize: 20)),
                const Text(
                  'Only the card brand and last four digits are stored.',
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cardBrand,
                        decoration: const InputDecoration(labelText: 'Brand'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: cardLast4,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Last 4'),
                      ),
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          if (!RegExp(r'^\d{4}$')
                              .hasMatch(cardLast4.text.trim())) {
                            throw StateError(
                              'Enter the last four card digits.',
                            );
                          }
                          await widget.store.setPaymentCard(
                            cardBrand.text.trim().isEmpty
                                ? 'Card'
                                : cardBrand.text.trim(),
                            cardLast4.text.trim(),
                          );
                          if (context.mounted) {
                            message(context, 'Payment card saved');
                          }
                        }),
                  child: const Text('Save payment card'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _manageSavedCards(context),
                  icon: const Icon(Icons.credit_card_outlined),
                  label: const Text('Manage saved cards'),
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
                          await widget.store.notifications.enable();
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
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('orders')
                      .where('userId', isEqualTo: widget.store.user!.uid)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Text(
                        'Orders could not load. Please try again.',
                      );
                    }
                    if (!snap.hasData) {
                      return const LinearProgressIndicator();
                    }
                    if (snap.data!.docs.isEmpty) {
                      return const Text(
                        'Your first local find is waiting for you.',
                      );
                    }
                    return Column(
                      children: snap.data!.docs
                          .map(
                            (d) => ListTile(
                              title: Text('Order ${d.id}'),
                              subtitle: Text(d.data()['status'].toString()),
                              trailing: Text(money(d.data()['total'] as num)),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
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
                DropdownButtonFormField<String>(
                  initialValue:
                      AppLocale.names.containsKey(widget.store.language)
                      ? widget.store.language
                      : 'en',
                  decoration: const InputDecoration(
                    labelText: 'Language / भाषा',
                  ),
                  items: AppLocale.names.entries
                      .where(
                        (entry) => AppLocale.enabled(
                          widget.store.business.text('enabledLanguages'),
                        ).any((locale) => locale.languageCode == entry.key),
                      )
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) run(() => widget.store.setLanguage(value));
                  },
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

  Future<void> _manageSavedCards(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Manage saved cards'),
        content: Text(
          widget.store.paymentLast4.isEmpty
              ? 'No saved cards.'
              : '${widget.store.paymentBrand} ending in ${widget.store.paymentLast4}',
        ),
        actions: [
          if (widget.store.paymentLast4.isNotEmpty)
            TextButton(
              onPressed: () async {
                try {
                  await widget.store.removePaymentCard();
                  if (dialog.mounted) Navigator.pop(dialog);
                } catch (e) {
                  if (dialog.mounted) message(dialog, e);
                }
              },
              child: const Text('Remove card'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
