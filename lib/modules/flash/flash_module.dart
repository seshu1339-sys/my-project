import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'flash_chat_page.dart';
import 'flash_data.dart';
import 'staff/staff_chat.dart';
import 'user/user_chat.dart';
import 'vendor/vendor_chat.dart';

/// The Flash module: three separate help chats (users, vendors, staff). Flash answers first on the server; what it cannot solve becomes a
/// ticket in the admin panel. No screen opens these yet: the owner will say where each chat goes, and that place calls one line below.
const flashRoute = '/flash';

const flashChats = [userFlashChat, vendorFlashChat, staffFlashChat];

Future<void> _open(BuildContext context, Store store, FlashChatSetup setup) => Navigator.of(context).push(
  MaterialPageRoute<void>(settings: RouteSettings(name: setup.route), builder: (_) => FlashChatPage(store: store, setup: setup)),
);

Future<void> openFlashUserChat(BuildContext context, Store store) => _open(context, store, userFlashChat);
Future<void> openFlashVendorChat(BuildContext context, Store store) => _open(context, store, vendorFlashChat);
Future<void> openFlashStaffChat(BuildContext context, Store store) => _open(context, store, staffFlashChat);
