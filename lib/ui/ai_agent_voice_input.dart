import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Mic button that turns speech into a text transcript and hands it to
/// [onTranscript] — the SAME submit path typed text already uses in
/// ai_agent_chat.dart/ai_agent_speaker_verification.dart. Removing this file
/// (and its one usage site) leaves typed text fully functional on its own.
///
/// Honesty note: iOS Safari only supports the underlying Web Speech API in an
/// actual Safari tab with network connectivity — NOT when the page was added
/// to the Home Screen as a standalone PWA. speech_to_text's own initialize()
/// call reports `false` in exactly that situation (no engine available), so
/// this widget surfaces that as the same disabled-with-explanation state
/// rather than needing its own separate standalone-mode detection.
class AiAgentVoiceInput extends StatefulWidget {
  const AiAgentVoiceInput({super.key, required this.onTranscript});
  final ValueChanged<String> onTranscript;
  @override
  State<AiAgentVoiceInput> createState() => _AiAgentVoiceInputState();
}

class _AiAgentVoiceInputState extends State<AiAgentVoiceInput> {
  final _speech = SpeechToText();
  bool _available = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _speech.initialize().then((ok) {
      if (mounted) setState(() => _available = ok);
    });
  }

  Future<void> _toggle() async {
    if (!_available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Voice input is unavailable here. If this page was added to the Home Screen, open the AI Agent link directly in Safari instead.'),
      ));
      return;
    }
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(onResult: (result) {
      if (result.finalResult) {
        widget.onTranscript(result.recognizedWords);
        if (mounted) setState(() => _listening = false);
      }
    });
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _listening ? 'Stop listening' : (_available ? 'Speak a command' : 'Voice input unavailable'),
    onPressed: _toggle,
    icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? Theme.of(context).colorScheme.error : null),
  );
}
