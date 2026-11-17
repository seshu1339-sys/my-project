import 'package:flutter/material.dart';

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
