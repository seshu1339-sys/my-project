import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'flash_chat_button.dart';
import 'flash_chat_page.dart';
import 'flash_data.dart';
import 'premium/premium_chat.dart';
import 'provider/provider_chat.dart';
import 'staff/staff_chat.dart';
import 'user/user_chat.dart';
import 'vendor/vendor_chat.dart';

export 'flash_chat_button.dart';

/// The Flash module: five separate help chats (customers, free vendors, Premium vendors, service providers, staff). Flash answers first
/// on the server from that person's own records; what it cannot solve becomes a ticket in the admin's Support Inbox. Every app opens
/// its chat from the floating Help button (owner decision, 6 November 2026): [customerFlashButton], [vendorAppFlashButton],
/// [staffAppFlashButton].
const flashRoute = '/flash';

const flashChats = [userFlashChat, vendorFlashChat, premiumFlashChat, providerFlashChat, staffFlashChat];

Future<void> _open(BuildContext context, Store store, FlashChatSetup setup) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: RouteSettings(name: setup.route), builder: (_) => FlashChatPage(store: store, setup: setup)),
);

Future<void> openFlashUserChat(BuildContext context, Store store) => _open(context, store, userFlashChat);
Future<void> openFlashVendorChat(BuildContext context, Store store) => _open(context, store, vendorFlashChat);
Future<void> openFlashPremiumChat(BuildContext context, Store store) => _open(context, store, premiumFlashChat);
Future<void> openFlashProviderChat(BuildContext context, Store store) => _open(context, store, providerFlashChat);
Future<void> openFlashStaffChat(BuildContext context, Store store) => _open(context, store, staffFlashChat);

/// Which chat the vendor app opens for this account: Premium (a running plan), a vendor (registered or approved), a service provider,
/// or the customers' chat for someone who has not registered yet. Decided from the server's records, never from the device.
Future<FlashChatSetup> vendorAppFlashSetup(Store store) async {
  final uid = store.user?.uid;
  if (uid == null) return userFlashChat;
  final db = store.firestore;
  // A record the rules do not let this login read counts as missing, so the chat always opens (an older rule refused a provider
  // login the vendor records, and an unregistered vendor the provider records: "The chat could not open: permission-denied").
  Future<Map<String, dynamic>?> read(String collection) async {
    try {
      return (await db.collection(collection).doc(uid).get()).data();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  final premium = await read('vendorPremium');
  if (premium?['active'] == true) return premiumFlashChat;
  if (await read('vendors') != null || await read('vendorApplications') != null) return vendorFlashChat;
  if (await read('providerApplications') != null || await read('providers') != null) return providerFlashChat;
  return userFlashChat;
}

/// The staff app's chat: the staff chat once registered, else the customers' chat (questions before registering).
Future<FlashChatSetup> staffAppFlashSetup(Store store) async {
  final uid = store.user?.uid;
  if (uid == null) return userFlashChat;
  return (await store.firestore.collection('fieldStaff').doc(uid).get()).exists ? staffFlashChat : userFlashChat;
}

Widget customerFlashButton(Store store, {Future<void> Function(BuildContext context)? onSignIn}) =>
    FlashChatButton(store: store, chooseSetup: () async => userFlashChat, open: (context, setup) => _open(context, store, setup), onSignIn: onSignIn);
Widget vendorAppFlashButton(Store store) => FlashChatButton(store: store, chooseSetup: () => vendorAppFlashSetup(store), open: (context, setup) => _open(context, store, setup));
Widget staffAppFlashButton(Store store) => FlashChatButton(store: store, chooseSetup: () => staffAppFlashSetup(store), open: (context, setup) => _open(context, store, setup));
