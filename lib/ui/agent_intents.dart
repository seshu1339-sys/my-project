import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/agent_command.dart';
import '../domain/agent_registry.dart';

/// The command box's flows beyond "open an option", each in its own file so one can change without the others:
///   health / healthPage   "what is not working?" and the Health page          (lib/ui/health_page.dart)
///   ad                    "this photo, Today's Offers, Narsipatnam, 10 km"      (lib/ui/agent_ad_flow.dart)
///   design                "make the search box wider"                          (lib/ui/agent_design_flow.dart)
class AgentIntentHandlers {
  const AgentIntentHandlers({required this.health, required this.healthPage, required this.ad, required this.design});

  /// The answer to "what is not working?" (one line per failure).
  final Future<String> Function(BuildContext context, Store store) health;
  final Widget Function(Store store) healthPage;
  final Future<void> Function(BuildContext context, Store store, AgentCommand command) ad;

  /// [matches] are the design options the words fit best (up to 3), [platform] the one chosen in step 1.
  final Future<void> Function(BuildContext context, Store store, AgentCommand command, List<RegistryEntry> matches, AgentPlatform? platform) design;
}

Future<String> _noHealth(BuildContext context, Store store) async => 'The health check is not set up yet.';
Future<void> _noFlow(BuildContext context, Store store, AgentCommand command) async {}
Future<void> _noDesign(BuildContext context, Store store, AgentCommand command, List<RegistryEntry> matches, AgentPlatform? platform) async {}

/// The flows the panel uses.
AgentIntentHandlers defaultAgentIntents = AgentIntentHandlers(
  health: _noHealth,
  healthPage: (_) => const Scaffold(body: Center(child: Text('Health'))),
  ad: _noFlow,
  design: _noDesign,
);
