import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/store.dart';
import 'flash_conversation.dart';
import 'flash_data.dart';
import '../../services/strings.dart';

/// One chat box: the person's own chats in this box. The screen itself is [FlashChatListView].
class FlashChatPage extends StatefulWidget {
  const FlashChatPage({super.key, required this.store, required this.setup});
  final Store store;
  final FlashChatSetup setup;

  @override
  State<FlashChatPage> createState() => _FlashChatPageState();
}

class _FlashChatPageState extends State<FlashChatPage> {
  Store get store => widget.store;
  FlashChatSetup get setup => widget.setup;
  late final chats = store.firestore.collection(setup.collection).where('uid', isEqualTo: store.user?.uid ?? '').orderBy('updatedAt', descending: true).limit(20).snapshots();

  void _open({required String category, String? chatId}) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => FlashConversationPage(store: store, setup: setup, category: category, chatId: chatId)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(setup.title)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: chats,
      builder: (context, found) {
        if (found.hasError) return Center(child: Text('Your chats could not load.'.tr(context)));
        if (!found.hasData) return const Center(child: CircularProgressIndicator());
        return FlashChatListView(
          top: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (setup.officeContact) FlashOfficeContact(store: store),
            // Vendors and providers may ask to be connected to the staff of their area; the admin chooses who (no staff ID needed).
            if (const {'vendor', 'premium', 'provider'}.contains(setup.kind)) LocalStaffRequestButton(store: store),
          ]),
          categories: setup.categories,
          chats: [for (final doc in found.data!.docs) FlashChat.fromData(doc.id, doc.data())],
          onNew: (category) => _open(category: category),
          onOpen: (chat) => _open(category: chat.category, chatId: chat.id),
        );
      },
    ),
  );
}

/// Choose a category to start, or open an earlier chat.
class FlashChatListView extends StatelessWidget {
  const FlashChatListView({super.key, required this.categories, required this.chats, required this.onNew, required this.onOpen, this.top});
  final List<String> categories;
  // Shown first (the Premium chat's office phone and WhatsApp).
  final Widget? top;
  final List<FlashChat> chats;
  final void Function(String category) onNew;
  final void Function(FlashChat chat) onOpen;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    ?top,
    Text('What do you need help with?'.tr(context), style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final category in categories) ActionChip(key: ValueKey('flash-new-$category'), label: Text(category), onPressed: () => onNew(category)),
    ]),
    if (chats.isNotEmpty) ...[
      const SizedBox(height: 20),
      Text('Your chats'.tr(context), style: Theme.of(context).textTheme.titleMedium),
      for (final chat in chats)
        ListTile(
          key: ValueKey('flash-chat-${chat.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(chat.category),
          subtitle: Text('${chat.statusLabel} · ${flashTime(chat.at)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpen(chat),
        ),
    ],
  ]);
}

/// The Premium chat's direct line to the office: Call and WhatsApp (Admin > Flash > Settings, kept in flashPublic/main).
class FlashOfficeContact extends StatelessWidget {
  const FlashOfficeContact({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('flashPublic').doc('main').snapshots(),
    builder: (context, snapshot) {
      final data = snapshot.data?.data() ?? const {};
      return FlashOfficeContactView(phone: '${data['supportPhone'] ?? ''}', whatsapp: '${data['supportWhatsapp'] ?? ''}');
    },
  );
}

class FlashOfficeContactView extends StatelessWidget {
  const FlashOfficeContactView({super.key, required this.phone, required this.whatsapp, this.launch});
  final String phone, whatsapp;
  // Test seam: how a link opens.
  final Future<void> Function(Uri uri)? launch;

  String _digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _go(Uri uri) => launch != null ? launch!(uri) : launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    if (phone.isEmpty && whatsapp.isEmpty) return const SizedBox.shrink();
    final wa = _digits(whatsapp.isEmpty ? phone : whatsapp);
    return Card(
      key: const ValueKey('flash-office'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Premium: talk to the LOCAMARKET office directly', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            if (phone.isNotEmpty)
              FilledButton.icon(key: const ValueKey('flash-office-call'), onPressed: () => _go(Uri(scheme: 'tel', path: _digits(phone))), icon: const Icon(Icons.call), label: const Text('Call')),
            if (wa.isNotEmpty)
              OutlinedButton.icon(
                key: const ValueKey('flash-office-whatsapp'),
                onPressed: () => _go(Uri.parse('https://wa.me/${wa.length == 10 ? '91$wa' : wa}')),
                icon: const Icon(Icons.chat),
                label: const Text('WhatsApp'),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// "Connect me to local staff": a request the admin sees (Admin > Staff > Link requests) and answers by choosing a staff member of the
/// vendor's or provider's area (functions/modules/staff-links requestLocalStaff).
class LocalStaffRequestButton extends StatelessWidget {
  const LocalStaffRequestButton({super.key, required this.store, this.send});
  final Store store;

  /// Test seam: sends the request.
  final Future<Map<String, dynamic>> Function()? send;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: OutlinedButton.icon(
      key: const ValueKey('flash-local-staff'),
      icon: const Icon(Icons.support_agent_outlined),
      label: const Text('Connect me to local staff'),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          final result = await (send ?? () => store.call('requestLocalStaff', const {}))();
          messenger.showSnackBar(SnackBar(content: Text(result['already'] == true
              ? 'You already asked. The Support Team will connect you to the staff of your area.'
              : 'Request sent. The Support Team will connect you to the staff of your area.')));
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''))));
        }
      },
    ),
  );
}
