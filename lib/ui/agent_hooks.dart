import 'package:flutter/widgets.dart';

import '../data/store.dart';

// Hooks the admin panel sets when it opens (lib/ui/admin.dart), like adminTabBuilder: they let a page (Health, a design change) open
// any command-box option by its ID without importing the registry, which would make an import loop through the Settings page.

/// Opens the option with this registry ID at its field (lib/ui/agent_open.dart). Null outside the admin panel.
Future<void> Function(BuildContext context, Store store, String id, {String command})? agentOpenById;

/// The name of the option with this registry ID ('' when unknown). Null outside the admin panel.
String Function(String id)? agentOptionName;
