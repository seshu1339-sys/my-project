import 'package:flutter/material.dart';

/// Asks for one line of text in a dialog and returns it (trimmed), or null when cancelled. The dialog owns its text box, so nothing is
/// used after it is gone (a controller disposed by the caller while the dialog is still closing breaks the app).
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? helper,
  String confirm = 'Save',
  TextInputType? keyboardType,
  int maxLines = 1,
  Key? fieldKey,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPromptDialog(title: title, label: label, initial: initial, helper: helper, confirm: confirm, keyboardType: keyboardType, maxLines: maxLines, fieldKey: fieldKey),
);

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.label, required this.initial, required this.helper, required this.confirm, required this.keyboardType, required this.maxLines, required this.fieldKey});
  final String title, label, initial, confirm;
  final String? helper;
  final TextInputType? keyboardType;
  final int maxLines;
  final Key? fieldKey;
  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: widget.fieldKey,
      controller: controller,
      autofocus: true,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      decoration: InputDecoration(labelText: widget.label, helperText: widget.helper),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(widget.confirm)),
    ],
  );
}
