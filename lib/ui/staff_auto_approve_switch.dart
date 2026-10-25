import 'package:flutter/material.dart';

/// Admin: the auto-approve switch of one field-staff member (off by default). On, what that staff member adds (vendors, service
/// providers) goes live without the admin once every photo passes the Google check; turning it on asks first. For trusted staff only.
class StaffAutoApproveSwitch extends StatelessWidget {
  const StaffAutoApproveSwitch({super.key, required this.staffName, required this.value, required this.onChanged});
  final String staffName;
  final bool value;
  final Future<void> Function(bool enabled) onChanged;

  Future<void> _change(BuildContext context, bool enabled) async {
    if (enabled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Auto-approve for $staffName?'),
          content: const Text('Every vendor and service provider this staff member adds will go live without your approval, once every photo passes the Google check. If a photo is found online, was used before, or cannot be checked, it waits for you. Turn it on only for staff you trust.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(key: const ValueKey('auto-approve-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Turn on')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    try {
      await onChanged(enabled);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled ? 'Auto-approve is on for $staffName.' : 'Auto-approve is off for $staffName: what they add waits for you.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    value: value,
    onChanged: (v) => _change(context, v),
    title: const Text('Auto-approve what they add'),
    subtitle: Text(value ? 'On: what they add goes live once every photo passes the Google check.' : 'Off: what they add waits for your approval.'),
  );
}
