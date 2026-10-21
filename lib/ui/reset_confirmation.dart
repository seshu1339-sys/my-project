import 'package:flutter/material.dart';

/// One line of a "reset to default" confirmation: a setting, what it is now and what it will be after the reset.
class ResetRow {
  const ResetRow(this.key, this.label, this.current, this.defaultText, {this.hidden = false});
  final String key, label, current, defaultText;
  // True for a stored value the form does not show (it still changes the site, so the reset clears it too).
  final bool hidden;
}

/// A stored value in words: "On"/"Off" for true/false, trimmed text, whole numbers without ".0".
String describeValue(Object? value) {
  if (value == null) return '(not set)';
  if (value is bool) return value ? 'On' : 'Off';
  if (value is num) return value == value.roundToDouble() ? '${value.round()}' : '$value';
  final text = '$value'.trim();
  if (text.isEmpty) return '(empty)';
  return text.length > 60 ? '${text.substring(0, 57)}…' : text;
}

/// Lists exactly what a reset will change (current -> default) and asks to confirm. Returns true only when the person confirms.
Future<bool> confirmReset(
  BuildContext context, {
  required String title,
  required String intro,
  required List<ResetRow> rows,
  String confirmLabel = 'Reset',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(intro),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  key: const ValueKey('reset-rows'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in rows)
                      Padding(
                        key: ValueKey('reset-row-${row.key}'),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: row.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (row.hidden) const TextSpan(text: ' (not shown in the form)', style: TextStyle(fontSize: 12)),
                              TextSpan(text: ':  ${row.current}  →  ${row.defaultText}'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(key: const ValueKey('reset-cancel'), onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('reset-confirm'), onPressed: () => Navigator.pop(dialog, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return ok == true;
}

/// Tells the person what a reset did, and that it was saved, in a dialog (a toast is too easy to miss).
Future<void> showResetDone(BuildContext context, {required String title, required List<ResetRow> rows, String? warning}) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('reset-done'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(warning, style: TextStyle(color: Theme.of(dialog).colorScheme.error, fontWeight: FontWeight.bold))),
            for (final row in rows) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${row.label}: ${row.current} → ${row.defaultText}')),
          ],
        ),
      ),
    ),
    actions: [FilledButton(key: const ValueKey('reset-done-ok'), onPressed: () => Navigator.pop(dialog), child: const Text('OK'))],
  ),
);
