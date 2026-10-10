import 'package:flutter/material.dart';

import '../data/store.dart';
import 'ai_agent_audit_log.dart';
import 'ai_agent_chat.dart';
import 'ai_agent_config.dart';
import 'ai_agent_gatekeeper.dart';
import 'ai_agent_monitoring.dart';
import 'ai_agent_pending_actions.dart';
import 'ai_agent_settings.dart';

/// The single lib/ui/admin.dart nav target for this whole optional module.
/// Deleting this file and its 2-line admin.dart entry (one import, one
/// navTargets map entry) removes the entire AI Admin Agent feature — nothing
/// else in the admin panel changes. Shows a plain disabled message when the
/// master switch is off, so the feature fails closed rather than crashing or
/// silently doing nothing when unconfigured.
class AiAgentPage extends StatefulWidget {
  const AiAgentPage({super.key, required this.store});
  final Store store;
  @override
  State<AiAgentPage> createState() => _AiAgentPageState();
}

class _AiAgentPageState extends State<AiAgentPage> with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 5, vsync: this);
  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AiAgentConfig>(
    stream: aiAgentConfigStream(widget.store),
    builder: (context, snapshot) {
      final config = snapshot.data ?? AiAgentConfig.disabled;
      return Scaffold(
        appBar: AppBar(
          title: const Text('AI Agent'),
          bottom: config.enabled
              ? TabBar(controller: tabs, isScrollable: true, tabs: const [
                  Tab(text: 'Chat'),
                  Tab(text: 'Pending actions'),
                  Tab(text: 'Audit log'),
                  Tab(text: 'Monitoring'),
                  Tab(text: 'Settings'),
                ])
              : null,
        ),
        body: !config.enabled
            ? _disabled(context)
            : AiAgentGatekeeper(
                store: widget.store,
                config: config,
                child: TabBarView(controller: tabs, children: [
                  AiAgentChat(store: widget.store, voiceEnabled: config.moduleEnabled('interpreter')),
                  AiAgentPendingActions(store: widget.store),
                  AiAgentAuditLogView(store: widget.store),
                  AiAgentMonitoring(store: widget.store),
                  AiAgentSettings(store: widget.store, config: config),
                ]),
              ),
      );
    },
  );

  Widget _disabled(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.smart_toy_outlined, size: 48),
        const SizedBox(height: 12),
        const Text('The AI Admin Agent is turned off.', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => widget.store.call('setAgentMasterEnabled', {'enabled': true}),
          child: const Text('Turn it on'),
        ),
      ]),
    ),
  );
}
