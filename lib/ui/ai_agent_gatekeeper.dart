import 'package:flutter/material.dart';

import '../data/store.dart';
import 'ai_agent_config.dart';
import 'ai_agent_speaker_verification.dart';
import 'ai_agent_trusted_device.dart';
import 'ai_agent_webauthn.dart';

enum _GateStatus { checking, needsDevice, needsFaceId, needsVoice, granted, denied }

/// Orders trusted-device -> Face ID -> voice before showing [child] — only
/// if every step whose module is enabled succeeds. Any disabled module
/// (per AiAgentConfig) is skipped entirely, so an admin can trade some of
/// this friction away deliberately; by default all three apply, matching the
/// spec's "verify trusted device, require Face ID, then verify voice; only
/// if both succeed, allow protected access; otherwise deny." This widget is
/// the one place that decision is made — removing it (and reverting
/// ai_agent_page.dart to show its child directly) is the only way to bypass it.
class AiAgentGatekeeper extends StatefulWidget {
  const AiAgentGatekeeper({super.key, required this.store, required this.config, required this.child});
  final Store store;
  final AiAgentConfig config;
  final Widget child;
  @override
  State<AiAgentGatekeeper> createState() => _AiAgentGatekeeperState();
}

class _AiAgentGatekeeperState extends State<AiAgentGatekeeper> {
  var status = _GateStatus.checking;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => status = _GateStatus.checking);
    if (widget.config.moduleEnabled('trustedDevice')) {
      final trusted = await verifyThisDeviceIsTrusted(widget.store);
      if (!trusted) {
        if (mounted) setState(() => status = _GateStatus.needsDevice);
        return;
      }
    }
    _nextAfterDevice();
  }

  void _nextAfterDevice() {
    if (widget.config.moduleEnabled('faceId')) {
      setState(() => status = _GateStatus.needsFaceId);
    } else {
      _nextAfterFaceId();
    }
  }

  void _nextAfterFaceId() {
    if (widget.config.moduleEnabled('speakerVerification')) {
      setState(() => status = _GateStatus.needsVoice);
    } else {
      setState(() => status = _GateStatus.granted);
    }
  }

  Future<void> _doFaceId() async {
    final ok = await verifyFaceId(context, widget.store);
    if (!ok) {
      if (mounted) setState(() => status = _GateStatus.denied);
      return;
    }
    _nextAfterFaceId();
  }

  Future<void> _doVoice() async {
    final ok = await verifyVoiceChallenge(context, widget.store);
    if (mounted) setState(() => status = ok ? _GateStatus.granted : _GateStatus.denied);
  }

  Widget _step({required IconData icon, required String message, required List<Widget> actions}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ...actions,
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _GateStatus.checking:
        return const Center(child: CircularProgressIndicator());
      case _GateStatus.needsDevice:
        return _step(
          icon: Icons.phone_iphone,
          message: 'Open this AI Agent link on the registered trusted Admin iPhone.',
          actions: [
            RegisterTrustedDeviceButton(store: widget.store, onRegistered: _nextAfterDevice),
            TextButton(onPressed: _run, child: const Text("I've registered — try again")),
          ],
        );
      case _GateStatus.needsFaceId:
        // The first admin to ever reach this gate has nothing registered yet
        // — registration must be reachable here, not only from the Settings
        // tab, since Settings itself sits behind this same gate.
        return _step(
          icon: Icons.face_retouching_natural,
          message: 'Register Face ID the first time, or verify it if you already have.',
          actions: [
            RegisterFaceIdButton(store: widget.store),
            const SizedBox(height: 8),
            FilledButton(onPressed: _doFaceId, child: const Text('Continue with Face ID')),
          ],
        );
      case _GateStatus.needsVoice:
        return _step(
          icon: Icons.record_voice_over,
          message: 'Enroll your passphrase the first time, or speak it to verify if you already have.',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Enroll my voice passphrase'),
              onPressed: () => showEnrollVoicePassphraseDialog(context, widget.store),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _doVoice, child: const Text('Verify my voice')),
          ],
        );
      case _GateStatus.denied:
        return _step(icon: Icons.block, message: 'Access denied.', actions: [TextButton(onPressed: _run, child: const Text('Try again'))]);
      case _GateStatus.granted:
        return widget.child;
    }
  }
}
