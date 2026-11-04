import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'admin_flash_chat.dart';
import 'admin_flash_settings.dart';
import 'flash_data.dart';
import 'flash_module.dart';

Widget _build(Store store) => AdminFlashPage(store: store);

/// The Flash tab of the admin panel (listed in module_admin.dart).
const flashAdminSection = ModuleAdminSection(id: 'flash', title: 'Flash', icon: Icons.support_agent_outlined, hint: 'Chats, tickets and what Flash knows', build: _build);

/// Admin > Flash: the three chats side by side but never mixed, each in its own tab, then the settings.
class AdminFlashPage extends StatelessWidget {
  const AdminFlashPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: flashChats.length + 1,
    child: Column(children: [
      TabBar(tabs: [for (final chat in flashChats) Tab(text: chat.adminTitle), const Tab(text: 'Settings')]),
      Expanded(
        child: TabBarView(children: [
          for (final chat in flashChats) _ChatTab(store: store, setup: chat),
          _SettingsTab(store: store),
        ]),
      ),
    ]),
  );
}

/// Reads one chat type for the admin. Its counts, tickets and solved chats never touch another type's.
class _ChatTab extends StatefulWidget {
  const _ChatTab({required this.store, required this.setup});
  final Store store;
  final FlashChatSetup setup;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  Store get store => widget.store;
  FlashChatSetup get setup => widget.setup;
  CollectionReference<Map<String, dynamic>> get _chats => store.firestore.collection(setup.collection);
  late final counts = store.firestore.collection('flashStats').doc(setup.kind).snapshots();
  late final tickets = store.firestore.collection('flashTickets').where('kind', isEqualTo: setup.kind).where('status', isEqualTo: 'open').snapshots();
  late final solved = _chats.where('status', isEqualTo: 'solved').where('verified', isEqualTo: false).limit(50).snapshots();

  Stream<FlashTriage?> _triage(String ticketId) => store.firestore.collection('flashTicketTriage').doc(ticketId).snapshots().map((doc) {
    final data = doc.data();
    return data == null ? null : FlashTriage.fromData(data);
  });

  Future<List<FlashMessage>> _messages(String chatId) async {
    final found = await _chats.doc(chatId).collection('messages').orderBy('at').get();
    return [for (final doc in found.docs) FlashMessage.fromData(doc.data())];
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: counts,
    builder: (context, countDoc) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: tickets,
      builder: (context, ticketDocs) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: solved,
        builder: (context, solvedDocs) {
          if (countDoc.hasError || ticketDocs.hasError || solvedDocs.hasError) return const Center(child: Text('Flash could not load.'));
          if (!countDoc.hasData || !ticketDocs.hasData || !solvedDocs.hasData) return const Center(child: CircularProgressIndicator());
          return AdminFlashChatView(
            counts: FlashCounts.fromData(countDoc.data!.data()),
            tickets: [for (final doc in ticketDocs.data!.docs) FlashTicket.fromData(doc.id, doc.data())]..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0))),
            solved: [for (final doc in solvedDocs.data!.docs) FlashChat.fromData(doc.id, doc.data())],
            triageOf: _triage,
            messagesOf: _messages,
            onClose: (ticketId, reply) => store.call('closeFlashTicket', {'ticketId': ticketId, 'reply': reply}),
            onVerify: (chatId) => store.call('verifyFlashChat', {'kind': setup.kind, 'chatId': chatId}),
          );
        },
      ),
    ),
  );
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('flashConfig').doc('main').snapshots(),
    builder: (context, config) {
      if (config.hasError) return const Center(child: Text('Flash settings could not load.'));
      // The boxes are filled once, so they wait for the saved values: empty ones must never be saved over them.
      if (!config.hasData) return const Center(child: CircularProgressIndicator());
      return AdminFlashSettings(config: FlashConfig.fromData(config.data!.data()), onSave: (fields) => store.call('saveFlashConfig', fields));
    },
  );
}
