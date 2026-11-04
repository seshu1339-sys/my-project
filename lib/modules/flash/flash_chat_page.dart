import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  const FlashChatListView({super.key, required this.categories, required this.chats, required this.onNew, required this.onOpen});
  final List<String> categories;
  final List<FlashChat> chats;
  final void Function(String category) onNew;
  final void Function(FlashChat chat) onOpen;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
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
