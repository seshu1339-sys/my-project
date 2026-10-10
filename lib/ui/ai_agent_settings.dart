import 'package:flutter/material.dart';

import '../data/store.dart';
import 'ai_agent_config.dart';
import 'ai_agent_confirmation.dart';
import 'ai_agent_speaker_verification.dart';
import 'ai_agent_trusted_device.dart';
import 'ai_agent_webauthn.dart';

const _moduleLabels = {
  'interpreter': 'Text/voice command interpretation',
  'content': 'Content & ad/ticker suggestions',
  'layout': 'Layout editor suggestions',
  'approvals': 'Vendor/staff approval actions',
  'imageCheck': 'Image licensing check',
  'trustedDevice': 'Trusted-device gate',
  'faceId': 'Face ID gate',
  'speakerVerification': 'Voice passphrase gate',
  'monitoring': 'Monitoring & email alerts',
  'backup': 'Backups',
  'github': 'GitHub integration',
  'playConsole': 'Google Play Console integration',
  'firebaseOps': 'Firebase Hosting/Functions status',
};

/// Manual-UI control method (the third of voice/text/manual, per the spec):
/// per-module on/off switches, provider pickers, and the one-time setup
/// actions (Agent PIN, trusted device, Face ID, voice passphrase). Every
/// toggle here writes through the exact same aiAgentConfig/global doc the
/// voice/text paths read from — one configuration system, no divergence.
class AiAgentSettings extends StatefulWidget {
  const AiAgentSettings({super.key, required this.store, required this.config});
  final Store store;
  final AiAgentConfig config;
  @override
  State<AiAgentSettings> createState() => _AiAgentSettingsState();
}

class _AiAgentSettingsState extends State<AiAgentSettings> {
  final githubAppId = TextEditingController();
  final githubInstallationId = TextEditingController();
  final playPackageName = TextEditingController();

  @override
  void initState() {
    super.initState();
    githubAppId.text = (widget.config.integrations['github']?['appId'] ?? '').toString();
    githubInstallationId.text = (widget.config.integrations['github']?['installationId'] ?? '').toString();
    playPackageName.text = (widget.config.integrations['playConsole']?['packageName'] ?? '').toString();
  }

  @override
  void dispose() {
    githubAppId.dispose();
    githubInstallationId.dispose();
    playPackageName.dispose();
    super.dispose();
  }

  Future<void> _setMaster(bool enabled) => widget.store.call('setAgentMasterEnabled', {'enabled': enabled});
  Future<void> _setModule(String moduleId, bool enabled) => widget.store.call('setAiAgentModuleEnabled', {'moduleId': moduleId, 'enabled': enabled});
  Future<void> _setLlmProvider(String provider) => widget.store.call('setAgentLlmProvider', {'provider': provider});
  Future<void> _setIntegrationSetting(String integration, String key, String value) async {
    try {
      await widget.store.call('setAgentIntegrationSetting', {'integration': integration, 'key': key, 'value': value});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    SwitchListTile(
      title: const Text('AI Admin Agent (master switch)'),
      subtitle: const Text('Turning this off disables every module below immediately.'),
      value: widget.config.enabled,
      onChanged: _setMaster,
    ),
    const Divider(),
    for (final entry in _moduleLabels.entries)
      SwitchListTile(
        title: Text(entry.value),
        value: widget.config.moduleEnabled(entry.key),
        onChanged: widget.config.enabled ? (v) => _setModule(entry.key, v) : null,
      ),
    const Divider(),
    ListTile(
      title: const Text('LLM provider for command interpretation'),
      subtitle: Text('Current: ${widget.config.llmProvider}. The rule-based parser always runs first and needs no provider at all.'),
      trailing: DropdownButton<String>(
        value: widget.config.llmProvider,
        items: const [
          DropdownMenuItem(value: 'none', child: Text('None (rule-based only)')),
          DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
          DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
        ],
        onChanged: (v) {
          if (v != null) _setLlmProvider(v);
        },
      ),
    ),
    ListTile(
      title: const Text('Voice verification provider'),
      subtitle: Text('Current: ${widget.config.voiceProvider}. Only "text-match" (passphrase transcript match) exists today.'),
    ),
    const Divider(),
    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Integration config (non-secret — real credentials are set server-side only)', style: TextStyle(fontWeight: FontWeight.bold))),
    Row(children: [
      Expanded(child: TextField(controller: githubAppId, decoration: const InputDecoration(labelText: 'GitHub App ID'))),
      IconButton(icon: const Icon(Icons.save), onPressed: () => _setIntegrationSetting('github', 'appId', githubAppId.text.trim())),
    ]),
    Row(children: [
      Expanded(child: TextField(controller: githubInstallationId, decoration: const InputDecoration(labelText: 'GitHub App installation ID'))),
      IconButton(icon: const Icon(Icons.save), onPressed: () => _setIntegrationSetting('github', 'installationId', githubInstallationId.text.trim())),
    ]),
    Row(children: [
      Expanded(child: TextField(controller: playPackageName, decoration: const InputDecoration(labelText: 'Play Console package name'))),
      IconButton(icon: const Icon(Icons.save), onPressed: () => _setIntegrationSetting('playConsole', 'packageName', playPackageName.text.trim())),
    ]),
    const Divider(),
    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('One-time setup', style: TextStyle(fontWeight: FontWeight.bold))),
    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: FilledButton.icon(
      icon: const Icon(Icons.pin),
      label: const Text('Set Agent PIN'),
      onPressed: () => showSetAgentPinDialog(context, widget.store),
    )),
    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: RegisterTrustedDeviceButton(store: widget.store)),
    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: RegisterFaceIdButton(store: widget.store)),
    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: FilledButton.icon(
      icon: const Icon(Icons.record_voice_over),
      label: const Text('Enroll voice passphrase'),
      onPressed: () => showEnrollVoicePassphraseDialog(context, widget.store),
    )),
  ]);
}
