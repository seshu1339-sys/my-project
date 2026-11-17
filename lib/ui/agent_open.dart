import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/agent_registry.dart';
import '../services/agent_log.dart';
import 'admin_android_sizes.dart';
import 'admin_settings.dart';
import 'agent_focus.dart';
import 'layout_editor.dart';

/// The page that holds one registry option, with its field marked for [AgentFocusTarget] (scrolled to and highlighted).
Widget agentPageFor(Store store, RegistryEntry e) {
  final Widget page;
  if (e.open.startsWith('layout:')) {
    page = LayoutSettingsPage(store: store, initialComponent: e.open.substring('layout:'.length));
  } else if (e.open == 'androidSizes') {
    // Only the sizes block, all of it built at once so the field can be scrolled to.
    page = Scaffold(appBar: AppBar(title: Text('Android App › ${e.name}')), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: AndroidSizesEditor(store: store)));
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

/// A risky step (suspend, delete, deactivate, approve / reject, All-India ads): the admin types YES (or అవును) to go on (owner spec I).
Future<bool> confirmRiskyAction(BuildContext context, {required String title, required String detail}) async =>
    await showDialog<bool>(context: context, builder: (_) => _RiskyDialog(title: title, detail: detail)) == true;

class _RiskyDialog extends StatefulWidget {
  const _RiskyDialog({required this.title, required this.detail});
  final String title, detail;
  @override
  State<_RiskyDialog> createState() => _RiskyDialogState();
}

class _RiskyDialogState extends State<_RiskyDialog> {
  final typed = TextEditingController();

  @override
  void dispose() {
    typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yes = {'yes', 'అవును'}.contains(typed.text.trim().toLowerCase());
    return AlertDialog(
      key: const ValueKey('agent-risky-confirm'),
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.detail),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('agent-risky-yes'),
          controller: typed,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Type YES (or అవును) to confirm', border: OutlineInputBorder()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('agent-risky-ok'), onPressed: yes ? () => Navigator.pop(context, true) : null, child: const Text('Confirm')),
      ],
    );
  }
}
