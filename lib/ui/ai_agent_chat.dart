import 'package:flutter/material.dart';

import '../data/store.dart';
import 'ai_agent_voice_input.dart';

class _ChatLine {
  const _ChatLine(this.text, {required this.fromAdmin});
  final String text;
  final bool fromAdmin;
}

/// Typed-text (and, via AiAgentVoiceInput, voice) command input. Every
/// submission goes through the same two calls regardless of its source:
/// interpretAgentCommand (text -> one whitelisted action) then
/// proposeAgentAction (write a preview for AiAgentPendingActions to show).
/// This widget never executes anything itself.
class AiAgentChat extends StatefulWidget {
  const AiAgentChat({super.key, required this.store, required this.voiceEnabled});
  final Store store;
  final bool voiceEnabled;
  @override
  State<AiAgentChat> createState() => _AiAgentChatState();
}

class _AiAgentChatState extends State<AiAgentChat> {
  final input = TextEditingController();
  final lines = <_ChatLine>[];
  bool busy = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || busy) return;
    setState(() {
      lines.add(_ChatLine(trimmed, fromAdmin: true));
      busy = true;
      input.clear();
    });
    try {
      final interpretation = await widget.store.call('interpretAgentCommand', {'text': trimmed});
      if (interpretation['kind'] == 'readOnly') {
        final result = await widget.store.call('queryAgentIntegration', {
          'query': interpretation['query'],
          'params': interpretation['params'],
        });
        setState(() => lines.add(_ChatLine('${result['data']}', fromAdmin: false)));
        return;
      }
      if (interpretation['action'] == 'unknown') {
        setState(() => lines.add(const _ChatLine('I could not match that to a known action. Try a more specific command.', fromAdmin: false)));
        return;
      }
      final proposal = await widget.store.call('proposeAgentAction', {
        'action': interpretation['action'],
        'params': interpretation['params'],
      });
      setState(() => lines.add(_ChatLine('Proposed: ${proposal['preview']}. Review it under "Pending actions" to apply or reject.', fromAdmin: false)));
    } catch (e) {
      setState(() => lines.add(_ChatLine('$e', fromAdmin: false)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Expanded(
      child: ListView.builder(
        reverse: true,
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[lines.length - 1 - i];
          return Align(
            alignment: line.fromAdmin ? Alignment.centerRight : Alignment.centerLeft,
            child: Card(
              color: line.fromAdmin ? Theme.of(context).colorScheme.primaryContainer : null,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(line.text)),
            ),
          );
        },
      ),
    ),
    Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        if (widget.voiceEnabled)
          AiAgentVoiceInput(onTranscript: (text) => _submit(text)),
        Expanded(
          child: TextField(
            controller: input,
            enabled: !busy,
            decoration: const InputDecoration(hintText: 'Type a command, e.g. "suspend vendor <id> for policy violation"', border: OutlineInputBorder()),
            onSubmitted: _submit,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: busy ? null : () => _submit(input.text),
          icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
        ),
      ]),
    ),
  ]);
}
