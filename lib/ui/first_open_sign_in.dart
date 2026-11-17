import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/strings.dart';
import 'sign_in_panel.dart';

/// The customer app and the website, first open after install: a sign-in sheet over the shop, and with it the Google sheet (on the
/// website Google's One Tap prompt) with the phone's Google email already shown, so signing in is one tap. Shown once on this phone
/// ([Store.offersSignInOnFirstOpen]); "Not now" or closing it lets the person shop without signing in, and Account signs in later.
/// It closes by itself once signed in.
class FirstOpenSignIn extends StatefulWidget {
  const FirstOpenSignIn({super.key, required this.store, required this.child});
  final Store store;
  final Widget child;
  @override
  State<FirstOpenSignIn> createState() => _FirstOpenSignInState();
}

class _FirstOpenSignInState extends State<FirstOpenSignIn> {
  @override
  void initState() {
    super.initState();
    if (!widget.store.offersSignInOnFirstOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !widget.store.offersSignInOnFirstOpen) return;
      await widget.store.firstOpenSignInShown();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => FirstOpenSignInSheet(store: widget.store),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The sheet itself: a welcome line, the sign-in (Google first, opening by itself) and "Not now".
class FirstOpenSignInSheet extends StatefulWidget {
  const FirstOpenSignInSheet({super.key, required this.store});
  final Store store;
  @override
  State<FirstOpenSignInSheet> createState() => _FirstOpenSignInSheetState();
}

class _FirstOpenSignInSheetState extends State<FirstOpenSignInSheet> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_closeWhenSignedIn);
  }

  void _closeWhenSignedIn() {
    if (_closed || widget.store.user == null || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.store.removeListener(_closeWhenSignedIn);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      key: const ValueKey('first-open-sign-in'),
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Welcome to LOCAMARKET'.tr(context), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Sign in once with your Google account and stay signed in.'.tr(context)),
          const SizedBox(height: 16),
          SignInPanel(store: widget.store),
          TextButton(
            key: const ValueKey('first-open-not-now'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Not now'.tr(context)),
          ),
        ],
      ),
    ),
  );
}
