import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'flash_data.dart';
import '../../services/strings.dart';

const _maxLetters = 1000;

/// One conversation: reads it, and sends through this chat's own endpoint. The server gives every answer. The screen is [FlashConversationView].
class FlashConversationPage extends StatefulWidget {
  const FlashConversationPage({super.key, required this.store, required this.setup, required this.category, this.chatId});
  final Store store;
  final FlashChatSetup setup;
  final String category;

  /// Null for a new chat: the server makes it with the first message.
  final String? chatId;

  @override
  State<FlashConversationPage> createState() => _FlashConversationPageState();
}

class _FlashConversationPageState extends State<FlashConversationPage> {
  String? chatId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? chat;
  Stream<QuerySnapshot<Map<String, dynamic>>>? messages;

  void _watch(String id) {
    final ref = widget.store.firestore.collection(widget.setup.collection).doc(id);
    chatId = id;
    chat = ref.snapshots();
    messages = ref.collection('messages').orderBy('at').snapshots();
  }

  @override
  void initState() {
    super.initState();
    if (widget.chatId case final id?) _watch(id);
  }

  Future<void> _send(String text) async {
    final result = await widget.store.call(widget.setup.callable, {
      'action': 'send',
      'text': text,
      if (chatId == null) 'category': widget.category else 'chatId': chatId,
    });
    if (chatId == null && mounted) setState(() => _watch(result['chatId'] as String));
  }

  Future<void> _mark(String action) => widget.store.call(widget.setup.callable, {'action': action, 'chatId': chatId});

  Widget _view(List<FlashMessage> talk, String status) => FlashConversationView(
    messages: talk,
    status: status,
    onSend: _send,
    onSolved: () => _mark('solved'),
    onUnsolved: () => _mark('unsolved'),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.category)),
    body: chatId == null
        ? _view(const [], 'open')
        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: chat,
            builder: (context, chatDoc) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messages,
              builder: (context, found) {
                if (chatDoc.hasError || found.hasError) return Center(child: Text('This chat could not load.'.tr(context)));
                final status = chatDoc.data?.data()?['status']?.toString();
                if (status == null || !found.hasData) return const Center(child: CircularProgressIndicator());
                return _view([for (final doc in found.data!.docs) FlashMessage.fromData(doc.data())], status);
              },
            ),
          ),
  );
}

/// The messages, then what the person can do next. Sending, "solved" and "not solved" go through the callbacks; no decision is made here.
class FlashConversationView extends StatefulWidget {
  const FlashConversationView({super.key, required this.messages, required this.status, required this.onSend, required this.onSolved, required this.onUnsolved});
  final List<FlashMessage> messages;
  final String status;
  final Future<void> Function(String text) onSend;
  final Future<void> Function() onSolved;
  final Future<void> Function() onUnsolved;

  @override
  State<FlashConversationView> createState() => _FlashConversationViewState();
}

class _FlashConversationViewState extends State<FlashConversationView> {
  final _text = TextEditingController();
  String? _sending;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Runs [action]; false when it failed, and the person is told why in the server's own words.
  Future<bool> _act(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    var done = true;
    try {
      await action();
    } catch (e) {
      done = false;
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), ''))));
    }
    if (mounted) setState(() => _busy = false);
    return done;
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _busy) return;
    _text.clear();
    setState(() => _sending = text);
    final sent = await _act(() => widget.onSend(text));
    if (!mounted) return;
    if (!sent) _text.text = text;
    setState(() => _sending = null);
  }

  // The message on its way, until the server's copy arrives.
  bool get _showSending => _sending != null && widget.messages.where((m) => m.role == 'user').lastOrNull?.text != _sending;
  bool get _flashAnswered => widget.messages.lastOrNull?.role == 'flash';

  Widget _bubble(FlashMessage message) {
    final mine = message.role == 'user';
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Card(
          color: mine ? colors.primaryContainer : colors.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (!mine) Text(message.role == 'admin' ? 'LOCAMARKET team' : 'Flash', style: Theme.of(context).textTheme.labelSmall),
              SelectableText(message.text),
            ]),
          ),
        ),
      ),
    );
  }

  Widget get _footer {
    if (widget.status == 'ticket') return const _Notice('flash-with-team', 'Your problem is with our team. Their answer will appear here.');
    if (widget.status != 'open') return const _Notice('flash-finished', 'This chat has finished. Go back to start a new one.');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_flashAnswered && !_busy)
        Wrap(spacing: 8, children: [
          TextButton.icon(key: const ValueKey('flash-solved'), onPressed: () => _act(widget.onSolved), icon: const Icon(Icons.check), label: Text('Problem solved'.tr(context))),
          TextButton.icon(key: const ValueKey('flash-unsolved'), onPressed: () => _act(widget.onUnsolved), icon: const Icon(Icons.support_agent), label: Text('Not solved'.tr(context))),
        ]),
      Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('flash-text'),
            controller: _text,
            maxLength: _maxLetters,
            minLines: 1,
            maxLines: 4,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(hintText: 'Type your message'.tr(context), counterText: ''),
          ),
        ),
        IconButton(key: const ValueKey('flash-send'), tooltip: 'Send'.tr(context), onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Expanded(
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (widget.messages.isEmpty && !_showSending) Text('Tell Flash what happened. If Flash cannot solve it, your problem goes to our team.'.tr(context)),
        for (final message in widget.messages) _bubble(message),
        if (_showSending) _bubble(FlashMessage(role: 'user', text: _sending!)),
        if (_busy) Padding(padding: EdgeInsets.all(8), child: Text('Flash is replying...'.tr(context), key: ValueKey('flash-busy'))),
      ]),
    ),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: _footer)),
  ]);
}

class _Notice extends StatelessWidget {
  const _Notice(this.id, this.text);
  final String id, text;

  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity, child: Text(text, key: ValueKey(id)));
}
