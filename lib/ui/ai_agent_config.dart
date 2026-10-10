import '../data/store.dart';

/// Reads the AI Admin Agent's config doc (aiAgentConfig/global, written only
/// by functions/ai-agent-config.js). Every other ai_agent_*.dart widget
/// checks this before showing anything — removing this file or leaving the
/// doc missing makes every module report disabled, never silently enabled.
class AiAgentConfig {
  const AiAgentConfig({required this.enabled, required this.modules, required this.llmProvider, required this.voiceProvider, required this.integrations});
  final bool enabled;
  final Map<String, bool> modules;
  final String llmProvider;
  final String voiceProvider;
  // Non-secret per-integration config (GitHub App id/installation id, Play
  // Console package name, ...) — {integration: {key: value}}. Real secrets
  // never appear here, only via `defineSecret` server-side.
  final Map<String, Map<String, dynamic>> integrations;

  static const disabled = AiAgentConfig(enabled: false, modules: {}, llmProvider: 'none', voiceProvider: 'text-match', integrations: {});

  factory AiAgentConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null) return disabled;
    final rawModules = data['modules'];
    final rawIntegrations = data['integrations'];
    return AiAgentConfig(
      enabled: data['enabled'] == true,
      modules: rawModules is Map ? rawModules.map((k, v) => MapEntry('$k', v == true)) : {},
      llmProvider: (data['llmProvider'] ?? 'none').toString(),
      voiceProvider: (data['voiceProvider'] ?? 'text-match').toString(),
      integrations: rawIntegrations is Map
          ? rawIntegrations.map((k, v) => MapEntry('$k', v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{}))
          : {},
    );
  }

  /// A module is enabled only when the master switch is on AND it hasn't
  /// been explicitly turned off (absence from the map means "on").
  bool moduleEnabled(String moduleId) => enabled && modules[moduleId] != false;
}

Stream<AiAgentConfig> aiAgentConfigStream(Store store) => store.firestore
    .collection('aiAgentConfig')
    .doc('global')
    .snapshots()
    .map((doc) => AiAgentConfig.fromMap(doc.data()));
