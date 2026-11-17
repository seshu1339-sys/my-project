import 'package:flutter/material.dart';

import '../services/strings.dart';

import '../data/store.dart';
import 'account_language_field.dart';
import 'layout_settings.dart';
import 'page_widgets.dart';
import 'sign_in_panel.dart';

/// The signed-out "Welcome to your neighbourhood" form of the customer app and the website: the language picker and the one sign-in
/// (SignInPanel): "Continue with Google" first, the 6-digit email code only when Google did not work. There is no password form and
/// no registration: signing in with Google or an email code is also how a new account is made, and an older password account signs in
/// the same way with its email (the same customer login).
class AccountAuthForm extends StatelessWidget {
  const AccountAuthForm({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      pageHeadingText(
        context,
        layout: layoutFor(context, store.entries('settings'), 'authFormHeading'),
        defaultText: 'Welcome to your neighbourhood',
        fontSize: 28,
      ),
      const SizedBox(height: 12),
      Text('Sign in with your Google account. It takes one tap.'.tr(context)),
      const SizedBox(height: 24),
      AccountLanguageField(store: store, onChanged: (value) => store.setLanguage(value)),
      const SizedBox(height: 14),
      // Not by itself here: the customer app opens Google by itself only once, on the first open (lib/ui/first_open_sign_in.dart).
      SignInPanel(store: store, opensGoogle: false),
    ],
  );
}
