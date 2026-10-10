import 'package:flutter/material.dart';

import '../data/store.dart';
import 'ai_agent_voice_input.dart';

/// Voice "speaker verification" step — honestly, a passphrase-knowledge
/// check (the browser transcribes speech, the server compares the
/// normalized text to a stored hash in functions/ai-agent-voice.js), not
/// true biometric voiceprint matching. That distinction is documented there,
/// not hidden. Removing this file denies protected access (fails closed).

Future<void> showEnrollVoicePassphraseDialog(BuildContext context, Store store) async {
  String? transcript;
  final typed = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Enroll your voice passphrase'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Speak (or type, if voice is unavailable) a short phrase only you will say to unlock protected AI Agent access.'),
        const SizedBox(height: 12),
        Row(children: [
          AiAgentVoiceInput(onTranscript: (text) => setDialogState(() => transcript = text)),
          Expanded(child: TextField(controller: typed, decoration: const InputDecoration(labelText: 'Passphrase'))),
        ]),
        if (transcript != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Heard: "$transcript"')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final phrase = (transcript ?? typed.text).trim();
            if (phrase.isEmpty) return;
            try {
              await store.call('enrollAgentVoicePassphrase', {'passphrase': phrase});
              if (dialog.mounted) Navigator.pop(dialog);
            } catch (e) {
              if (dialog.mounted) ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(content: Text('$e')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    )),
  );
}

/// Shows a "speak your passphrase" challenge and returns true only if the
/// server confirms the transcript matches the enrolled passphrase.
Future<bool> verifyVoiceChallenge(BuildContext context, Store store) async {
  String? transcript;
  final typed = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Speak your passphrase'),
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        AiAgentVoiceInput(onTranscript: (text) => setDialogState(() => transcript = text)),
        Expanded(child: TextField(controller: typed, decoration: const InputDecoration(labelText: 'Passphrase'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final phrase = (transcript ?? typed.text).trim();
            if (phrase.isEmpty) return;
            try {
              await store.call('verifyAgentVoice', {'transcript': phrase});
              if (dialog.mounted) Navigator.pop(dialog, true);
            } catch (e) {
              if (dialog.mounted) {
                ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(content: Text('$e')));
                Navigator.pop(dialog, false);
              }
            }
          },
          child: const Text('Verify'),
        ),
      ],
    )),
  );
  return result == true;
}
