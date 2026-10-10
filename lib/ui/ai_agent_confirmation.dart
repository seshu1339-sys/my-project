import 'package:flutter/material.dart';

import '../data/store.dart';

/// Confirmation for sensitive/critical AI Agent actions. 'sensitive' uses a
/// short Agent PIN (set once here, verified server-side in
/// functions/ai-agent-confirmation.js). 'critical' reuses the EXISTING
/// requestAdminOtp/verifyAdminOtp email flow unmodified — no new email code
/// anywhere in this file. Removing this file means no sensitive/critical
/// action can ever be confirmed (fails closed, not open).

Future<void> showSetAgentPinDialog(BuildContext context, Store store) async {
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Set your Agent PIN'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('This PIN confirms sensitive AI Agent actions (approvals, suspensions, etc.). It is separate from your login password.'),
        const SizedBox(height: 12),
        TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New PIN (4-8 digits)')),
        TextField(controller: confirmPin, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm PIN')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true) return;
  if (pin.text.trim() != confirmPin.text.trim()) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PINs did not match.')));
    return;
  }
  try {
    await store.call('setAgentPin', {'pin': pin.text.trim()});
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Agent PIN saved.')));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// Returns the entered PIN, or null if the admin cancelled.
Future<String?> promptAgentPin(BuildContext context, String preview) async {
  final pin = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Confirm with your Agent PIN'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(preview),
        const SizedBox(height: 12),
        TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Agent PIN')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Confirm')),
      ],
    ),
  );
  return ok == true ? pin.text.trim() : null;
}

/// For 'critical' tier: walks the admin through the EXISTING OTP email round
/// (requestAdminOtp -> verifyAdminOtp, unmodified) right before confirming a
/// critical action, so confirmAgentAction's server-side recency check passes.
/// Returns true only if a code was actually verified.
Future<bool> ensureFreshOtp(BuildContext context, Store store, String preview) async {
  try {
    await store.call('requestAdminOtp', const {});
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
  if (!context.mounted) return false;
  final code = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Critical action — verify your code'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(preview),
        const SizedBox(height: 8),
        const Text('A verification code was emailed to your administrator account.'),
        TextField(controller: code, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: '6-digit code')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Verify')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await store.call('verifyAdminOtp', {'code': code.text.trim()});
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}
