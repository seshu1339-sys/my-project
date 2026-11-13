import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/search_providers.dart';

/// Admin > Settings > AI assistant: the admin asks about the numbers in plain words (typed or spoken) and Claude Sonnet 5.5 answers
/// from today's counts (functions/modules/admin-assistant: read-only, a daily limit the admin sets in Business Profile). The voice is
/// turned into text on the device; only the text goes to the server.
class AdminAiAssistantPage extends StatefulWidget {
  const AdminAiAssistantPage({super.key, required this.store, this.ask, this.listen});
  final Store store;

  /// Test seams: the server call and the voice input.
  final Future<String> Function(String question)? ask;
  final Future<String> Function()? listen;

  @override
  State<AdminAiAssistantPage> createState() => _AdminAiAssistantPageState();
}

class _AdminAiAssistantPageState extends State<AdminAiAssistantPage> {
  final question = TextEditingController();
  final answers = <(String, String)>[];
  bool busy = false;
  String? error;

  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  Future<String> _ask(String q) async {
    final result = await widget.store.call('askAdminAssistant', {'question': q});
    return '${result['answer'] ?? ''}';
  }

  Future<void> _send() async {
    final q = question.text.trim();
    if (q.isEmpty || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final answer = await (widget.ask ?? _ask)(q);
      if (!mounted) return;
      setState(() {
        answers.insert(0, (q, answer));
        question.clear();
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _voice() async {
    try {
      final text = await (widget.listen ?? DeviceVoiceSearch(localeId: voiceLocaleFor(widget.store.language)).transcribe)();
      if (!mounted) return;
      question.text = text;
      await _send();
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Ask about your numbers: vendors waiting, offers running, payments, open tickets. It reads today\'s counts and changes nothing.'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('ai-assistant-question'),
            controller: question,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(labelText: 'Your question (Telugu or English)', border: OutlineInputBorder()),
          ),
        ),
        IconButton(key: const ValueKey('ai-assistant-mic'), tooltip: 'Speak', onPressed: busy ? null : _voice, icon: const Icon(Icons.mic_none)),
        FilledButton(key: const ValueKey('ai-assistant-ask'), onPressed: busy ? null : _send, child: Text(busy ? 'Asking…' : 'Ask')),
      ]),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, key: const ValueKey('ai-assistant-error'), style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 12),
      for (final (i, (q, a)) in answers.indexed)
        Card(
          key: ValueKey('ai-assistant-answer-$i'),
          child: ListTile(title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: SelectableText(a)),
        ),
    ],
  );
}
