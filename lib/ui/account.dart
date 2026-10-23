import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/store.dart';
import '../services/strings.dart';
import 'layout_settings.dart';
import 'page_widgets.dart';
import 'shared.dart';
import 'account_auth_form.dart';
import 'location_picker_dialog.dart';
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
  Widget build(BuildContext context) {
    final titleLayout = layoutFor(
      context,
      widget.store.entries('settings'),
      'accountPageAppBarTitle',
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleLayout.entry.text('text', 'Your account').tr(context),
          style: overrideTextStyle(titleLayout.entry),
        ),
      ),
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
                  pageHeadingText(
                    context,
                    layout: layoutFor(
                      context,
                      widget.store.entries('settings'),
                      'accountDemoHeading',
                    ),
                    defaultText: 'You’re exploring the demo',
                    fontSize: 26,
                    fontWeight: FontWeight.normal,
                  ),
                  Text('Email sign-in and orders become available when Firebase is connected. Browse products and try the cart freely.'.tr(context)),
                ] else if (widget.store.user != null &&
                    !widget.store.user!.emailVerified) ...[
                  Text(
                    'Verify your email'.tr(context),
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Open the verification link sent to {email}, then return here. Check your spam folder too.'.tr(
                      context,
                      {'email': widget.store.user!.email ?? 'your email'.tr(context)},
                    ),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final verified = await widget.store
                                .refreshEmailVerification();
                            if (context.mounted && !verified) {
                              message(context, 'Your email is not verified yet. Open the email link first.'.tr(context));
                            }
                          }),
                    child: Text('I have verified my email'.tr(context)),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await widget.store.sendVerificationEmail();
                            if (context.mounted) {
                              message(context, 'Verification email sent'.tr(context));
                            }
                          }),
                    child: Text('Resend verification email'.tr(context)),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => run(widget.store.logout),
                    child: Text('Log out / Use another email'.tr(context)),
                  ),
                ] else if (widget.store.user != null) ...[
                  Text(
                    widget.store.user!.email ?? 'Your profile'.tr(context),
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: 'Your name'.tr(context)),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await widget.store.updateProfile(name.text.trim());
                            if (context.mounted) {
                              message(context, 'Profile saved'.tr(context));
                            }
                          }),
                    child: Text('Save profile'.tr(context)),
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
                              message(context, 'If an account exists, a password reset email has been sent.'.tr(context));
                            }
                          }),
                    child: Text('Reset password by email'.tr(context)),
                  ),
                  TextButton(
                    onPressed: () => run(widget.store.logout),
                    child: Text('Log out'.tr(context)),
                  ),
                  const Divider(),
                  Text('Get price-drop alerts for items you view and new offer notifications. Your signed-in item views are saved privately to personalize these alerts.'.tr(context)),
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
                              message(context, 'Price-drop and offer alerts enabled'.tr(context));
                              // Offers are sent for the customer's town, so alerts need a location.
                              if (!widget.store.hasPlace) {
                                message(context, 'Choose your location so we can send offers for your town.'.tr(context));
                                await showLocationPickerDialog(context, widget.store);
                              }
                            }
                          }),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text('Enable alerts on this device'.tr(context)),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await widget.store.notifications.disable();
                            if (context.mounted) {
                              message(context, 'Alerts disabled'.tr(context));
                            }
                          }),
                    child: Text('Disable alerts for my account'.tr(context)),
                  ),
                  pageHeadingText(
                    context,
                    layout: layoutFor(
                      context,
                      widget.store.entries('settings'),
                      'accountOrdersHeading',
                    ),
                    defaultText: 'Your orders',
                    fontSize: 22,
                    fontWeight: FontWeight.normal,
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => complaint_dialog.showComplaintDialog(
                            context,
                            widget.store,
                            run,
                          ),
                    icon: const Icon(Icons.report_problem_outlined),
                    label: Text('Open a complaint'.tr(context)),
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
}
