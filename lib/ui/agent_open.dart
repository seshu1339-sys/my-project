import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/agent_registry.dart';
import '../services/agent_log.dart';
import 'admin_android_sizes.dart';
import 'admin_settings.dart';
import 'design_pages.dart';
import 'agent_focus.dart';
import 'layout_editor.dart';
export 'agent_confirm.dart';

/// The page that holds one registry option, with its field marked for [AgentFocusTarget] (scrolled to and highlighted).
Widget agentPageFor(Store store, RegistryEntry e) {
  final Widget page;
  if (e.open.startsWith('layout:')) {
    page = LayoutSettingsPage(store: store, initialComponent: e.open.substring('layout:'.length));
  } else if (e.open == 'androidSizes') {
    // Only the sizes block, all of it built at once so the field can be scrolled to.
    page = Scaffold(appBar: AppBar(title: Text('Android App › ${e.name}')), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: AndroidSizesEditor(store: store)));
  } else if (e.open == 'designTexts') {
    page = Scaffold(appBar: AppBar(title: const Text('Design texts & sizes')), body: DesignTextsPage(store: store));
  } else {
    page = adminSettingsSectionPage(store, e.open, focus: e.kind == RegistryKind.page ? null : e.name);
  }
  return AgentFocusScope(field: e.field, child: page);
}

/// Opens [e] on top of the panel and logs it. [command] is what the admin typed or said.
Future<void> openAgentEntry(BuildContext context, Store store, RegistryEntry e, {String command = '', String platform = ''}) {
  AgentLog.write(store, action: 'open', command: command, target: e.id, platform: platform);
  return Navigator.push(context, MaterialPageRoute<void>(builder: (_) => agentPageFor(store, e)));
}

