import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/agent_command.dart';
import '../domain/agent_registry.dart';
import 'agent_ad_flow.dart';
import 'agent_design_flow.dart';
import 'health_page.dart';

/// The command box's flows beyond "open an option", each in its own file so one can change without the others:
///   health / healthPage   "what is not working?" and the Health page          (lib/ui/health_page.dart)
///   ad                    "this photo, Today's Offers, Narsipatnam, 10 km"      (lib/ui/agent_ad_flow.dart)
///   design                "make the search box wider"                          (lib/ui/agent_design_flow.dart)
class AgentIntentHandlers {
  const AgentIntentHandlers({required this.health, required this.healthPage, required this.ad, required this.design});

  /// The answer to "what is not working?" (one line per failure).
  final Future<String> Function(BuildContext context, Store store) health;
  final Widget Function(Store store) healthPage;
  /// [photo] is the photo attached in the command box ("this photo, ..."), or null.
  final Future<void> Function(BuildContext context, Store store, AgentCommand command, XFile? photo) ad;

  /// [matches] are the design options the words fit best (up to 3), [platform] the one chosen in step 1.
  final Future<void> Function(BuildContext context, Store store, AgentCommand command, List<RegistryEntry> matches, AgentPlatform? platform) design;
}


/// The flows the panel uses.
AgentIntentHandlers defaultAgentIntents = AgentIntentHandlers(
  health: (context, store) => answerNotWorking(store),
  healthPage: (store) => Scaffold(appBar: AppBar(title: const Text('Health')), body: HealthPage(store: store)),
  ad: (context, store, command, photo) => openAdFlow(context, store, command, photo: photo),
  design: openDesignFlow,
);
