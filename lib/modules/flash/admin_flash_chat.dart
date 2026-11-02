import 'package:flutter/material.dart';

import 'flash_data.dart';

/// One chat type in the admin panel: how many came in, were solved and are pending; the open tickets; and what Flash solved, to check.
class AdminFlashChatView extends StatelessWidget {
  const AdminFlashChatView({super.key, required this.counts, required this.tickets, required this.solved, required this.triageOf, required this.messagesOf, required this.onClose, required this.onVerify});
  final FlashCounts counts;
  final List<FlashTicket> tickets;
  final List<FlashChat> solved;
  final Stream<FlashTriage?> Function(String ticketId) triageOf;
  final Future<List<FlashMessage>> Function(String chatId) messagesOf;
  final Future<void> Function(String ticketId, String reply) onClose;
  final Future<void> Function(String chatId) onVerify;

  Future<void> _verify(BuildContext context, FlashChat chat) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await onVerify(chat.id);
      messenger.showSnackBar(const SnackBar(content: Text('Verified')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Wrap(spacing: 8, runSpacing: 8, children: [
      _Count('flash-came-in', 'Came in', counts.cameIn),
      _Count('flash-solved-count', 'Solved', counts.solved),
      _Count('flash-pending', 'Pending', counts.pending),
      _Count('flash-verified-count', 'Verified', counts.verified),
    ]),
    const SizedBox(height: 16),
    Text('Open tickets', style: Theme.of(context).textTheme.titleLarge),
    if (tickets.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No open tickets.', key: ValueKey('flash-no-tickets')))),
    for (final ticket in tickets) _TicketCard(key: ValueKey('flash-ticket-${ticket.id}'), ticket: ticket, triageOf: triageOf, messagesOf: messagesOf, onClose: onClose),
    const SizedBox(height: 16),
    Text('Solved by Flash, to check', style: Theme.of(context).textTheme.titleLarge),
    if (solved.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nothing to check.', key: ValueKey('flash-none-solved')))),
    for (final chat in solved)
      Card(
        key: ValueKey('flash-solved-${chat.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${chat.category}: ${_who(chat.who, chat.email)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(flashTime(chat.at)),
            Wrap(spacing: 4, children: [
              TextButton(key: ValueKey('flash-view-${chat.id}'), onPressed: () => _showChat(context, messagesOf(chat.id)), child: const Text('View chat')),
              TextButton(key: ValueKey('flash-verify-${chat.id}'), onPressed: () => _verify(context, chat), child: const Text('Verified')),
            ]),
          ]),
        ),
      ),
  ]);
}

String _who(String who, String email) => [who, email].where((part) => part.isNotEmpty).join(' · ');

Future<void> _showChat(BuildContext context, Future<List<FlashMessage>> messages) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    title: const Text('Chat'),
    content: SizedBox(
      width: 480,
      child: FutureBuilder<List<FlashMessage>>(
        future: messages,
        builder: (context, found) {
          if (found.hasError) return const Text('This chat could not load.');
          if (!found.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
          return ListView(shrinkWrap: true, children: [
            for (final message in found.data!) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${message.role == 'user' ? 'Person' : message.role == 'admin' ? 'Admin' : 'Flash'}: ${message.text}')),
          ]);
        },
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close'))],
  ),
);

class _Count extends StatelessWidget {
  const _Count(this.id, this.label, this.value);
  final String id, label;
  final int value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', key: ValueKey(id), style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ]),
    ),
  );
}

/// One open ticket with its AI suggestion. The suggestion changes nothing; only the admin's answer closes the ticket.
class _TicketCard extends StatefulWidget {
  const _TicketCard({super.key, required this.ticket, required this.triageOf, required this.messagesOf, required this.onClose});
  final FlashTicket ticket;
  final Stream<FlashTriage?> Function(String ticketId) triageOf;
  final Future<List<FlashMessage>> Function(String chatId) messagesOf;
  final Future<void> Function(String ticketId, String reply) onClose;

  @override
  State<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<_TicketCard> {
  late final triage = widget.triageOf(widget.ticket.id);

  Future<void> _close() async {
    final messenger = ScaffoldMessenger.of(context);
    final reply = await showDialog<String>(context: context, builder: (_) => const _AnswerDialog());
    if (reply == null) return;
    try {
      await widget.onClose(widget.ticket.id, reply);
      messenger.showSnackBar(const SnackBar(content: Text('Ticket closed')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${ticket.category}: ${_who(ticket.who, ticket.email)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${flashTime(ticket.at)} · ${ticket.reasonLabel}'),
          if (ticket.summary.isNotEmpty) Text(ticket.summary),
          const SizedBox(height: 6),
          SelectableText(ticket.text),
          const SizedBox(height: 6),
          StreamBuilder<FlashTriage?>(
            stream: triage,
            builder: (context, found) {
              final reading = found.data;
              final text = reading == null
                  ? 'AI is reading this ticket...'
                  : reading.failed
                      ? 'AI could not read this ticket.'
                      : 'AI suggestion, nothing has been done: ${reading.type}, ${reading.urgency} urgency. ${reading.suggestion}';
              return Text(text, key: ValueKey('flash-triage-${ticket.id}'), style: const TextStyle(fontStyle: FontStyle.italic));
            },
          ),
          Wrap(spacing: 4, children: [
            TextButton(key: ValueKey('flash-view-${ticket.chatId}'), onPressed: () => _showChat(context, widget.messagesOf(ticket.chatId)), child: const Text('View chat')),
            TextButton(key: ValueKey('flash-close-${ticket.id}'), onPressed: _close, child: const Text('Answer and close')),
          ]),
        ]),
      ),
    );
  }
}

class _AnswerDialog extends StatefulWidget {
  const _AnswerDialog();

  @override
  State<_AnswerDialog> createState() => _AnswerDialogState();
}

class _AnswerDialogState extends State<_AnswerDialog> {
  final _answer = TextEditingController();

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Answer and close'),
    content: TextField(
      key: const ValueKey('flash-answer'),
      controller: _answer,
      maxLength: 1000,
      minLines: 2,
      maxLines: 5,
      decoration: const InputDecoration(labelText: 'This appears in the person\'s chat'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('flash-answer-send'), onPressed: () => Navigator.pop(context, _answer.text.trim()), child: const Text('Send and close')),
    ],
  );
}
