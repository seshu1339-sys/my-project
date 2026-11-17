import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'flash_data.dart';

/// The floating chat button at the bottom right of every app's main screen. A tap opens the right chat for this account
/// ([chooseSetup], decided from the server's records: customer, free vendor, Premium vendor, service provider or staff). Signed out,
/// it asks to sign in first ([onSignIn]).
class FlashChatButton extends StatelessWidget {
  const FlashChatButton({super.key, required this.store, required this.chooseSetup, required this.open, this.onSignIn});
  final Store store;
  final Future<FlashChatSetup> Function() chooseSetup;
  final Future<void> Function(BuildContext context, FlashChatSetup setup) open;
  final Future<void> Function(BuildContext context)? onSignIn;

  Future<void> _tap(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (store.user == null) {
      if (onSignIn != null) return onSignIn!(context);
      messenger.showSnackBar(const SnackBar(content: Text('Sign in to chat with the Support Team.')));
      return;
    }
    try {
      final setup = await chooseSetup();
      if (context.mounted) await open(context, setup);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('The chat could not open: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    key: const ValueKey('flash-chat-button'),
    heroTag: 'flash-chat-button',
    tooltip: 'Help chat',
    onPressed: () => _tap(context),
    icon: const Icon(Icons.chat_bubble_outline),
    label: const Text('Help'),
  );
}
