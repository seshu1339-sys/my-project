import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import '../services/localization.dart';
import 'shared.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.store});
  final Store store;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final phone = TextEditingController(text: '+91'),
      pin = TextEditingController(),
      code = TextEditingController(),
      name = TextEditingController();
  String? verificationId;
  ConfirmationResult? confirmation;
  bool recovery = false, sent = false, verified = false, busy = false;
  final cardBrand = TextEditingController(),
      cardLast4 = TextEditingController();
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
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

  Future<void> send() async {
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone.text.trim())) {
      throw StateError('Enter your phone number with country code.');
    }
    if (kIsWeb) {
      confirmation = await FirebaseAuth.instance.signInWithPhoneNumber(
        phone.text.trim(),
      );
      sent = true;
    } else {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone.text.trim(),
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          if (mounted) {
            setState(() => verified = true);
          }
        },
        verificationFailed: (e) {
          if (mounted) {
            message(context, e.message ?? 'Verification failed');
          }
        },
        codeSent: (id, token) {
          if (mounted) {
            setState(() {
              verificationId = id;
              sent = true;
            });
          }
        },
        codeAutoRetrievalTimeout: (id) => verificationId = id,
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
    phone.dispose();
    pin.dispose();
    code.dispose();
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
                  'Phone sign-in and orders become available when Firebase is connected. Browse products and try the cart freely.',
                ),
              ] else if (widget.store.user != null && !recovery) ...[
                Text(
                  widget.store.user!.phoneNumber ?? 'Your profile',
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
                    if (value != null) {
                      widget.store.setLanguage(value);
                    }
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
                  onPressed: () => setState(() {
                    recovery = true;
                    phone.text = widget.store.user!.phoneNumber ?? '+91';
                  }),
                  child: const Text('Change PIN with SMS verification'),
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
                  recovery
                      ? 'Verify your mobile'
                      : 'Welcome to your neighbourhood',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  recovery
                      ? 'New account or forgot PIN? Verify your number by SMS, then choose a six-digit PIN.'
                      : 'Sign in with your mobile number and six-digit PIN.',
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
                    if (value != null) widget.store.setLanguage(value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number (+91…)',
                  ),
                ),
                const SizedBox(height: 14),
                if (!recovery || verified)
                  TextField(
                    controller: pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: verified
                          ? 'New six-digit PIN'
                          : 'Six-digit PIN',
                    ),
                  ),
                if (recovery && !verified) ...[
                  const Text(
                    'By continuing, you agree to receive a verification SMS. Your number is processed by Google for authentication and abuse prevention.',
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => run(send),
                    child: Text(sent ? 'Resend SMS code' : 'Send SMS code'),
                  ),
                  if (sent) ...[
                    TextField(
                      controller: code,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'SMS code'),
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              if (kIsWeb) {
                                await confirmation!.confirm(code.text.trim());
                              } else {
                                await FirebaseAuth.instance
                                    .signInWithCredential(
                                      PhoneAuthProvider.credential(
                                        verificationId: verificationId!,
                                        smsCode: code.text.trim(),
                                      ),
                                    );
                              }
                              verified = true;
                            }),
                      child: const Text('Verify number'),
                    ),
                  ],
                ] else
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            if (!RegExp(r'^\d{6}$').hasMatch(pin.text)) {
                              throw StateError('Use exactly six digits.');
                            }
                            if (verified) {
                              await widget.store.setPin(pin.text);
                              recovery = false;
                              verified = false;
                            } else {
                              await widget.store.login(
                                phone.text.trim(),
                                pin.text,
                              );
                            }
                          }),
                    child: Text(verified ? 'Save new PIN' : 'Sign in'),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => recovery = !recovery),
                  child: Text(
                    recovery
                        ? 'Back to PIN sign-in'
                        : 'Create account / Forgot PIN',
                  ),
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
                await widget.store.removePaymentCard();
                if (dialog.mounted) Navigator.pop(dialog);
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
