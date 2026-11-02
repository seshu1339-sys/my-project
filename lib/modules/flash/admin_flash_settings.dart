import 'package:flutter/material.dart';

import 'flash_data.dart';

/// Admin > Flash > Settings: the daily message limit, and what Flash knows about using each app. With a box empty, Flash sends how-to
/// questions for that app to the team instead of making up steps.
class AdminFlashSettings extends StatefulWidget {
  const AdminFlashSettings({super.key, required this.config, required this.onSave});
  final FlashConfig config;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  @override
  State<AdminFlashSettings> createState() => _AdminFlashSettingsState();
}

class _AdminFlashSettingsState extends State<AdminFlashSettings> {
  late final _limit = TextEditingController(text: '${widget.config.dailyMessages}');
  late final _user = TextEditingController(text: widget.config.helpUser);
  late final _vendor = TextEditingController(text: widget.config.helpVendor);
  late final _staff = TextEditingController(text: widget.config.helpStaff);
  bool _busy = false;

  @override
  void dispose() {
    for (final box in [_limit, _user, _vendor, _staff]) {
      box.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final limit = int.tryParse(_limit.text.trim());
    if (limit == null) {
      messenger.showSnackBar(const SnackBar(content: Text('The daily limit must be a number.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSave({'dailyMessages': limit, 'helpUser': _user.text, 'helpVendor': _vendor.text, 'helpStaff': _staff.text});
      messenger.showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _help(String id, String label, TextEditingController box) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey(id),
      controller: box,
      maxLength: 4000,
      minLines: 3,
      maxLines: 8,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true, border: const OutlineInputBorder()),
    ),
  );

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    TextField(
      key: const ValueKey('flash-limit'),
      controller: _limit,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Messages each person can send in a day', border: OutlineInputBorder()),
    ),
    const SizedBox(height: 12),
    const Text('What Flash knows about using the apps. If a box is empty, Flash sends how-to questions to the team.'),
    _help('flash-help-user', 'User app help', _user),
    _help('flash-help-vendor', 'Vendor app help', _vendor),
    _help('flash-help-staff', 'Staff app help', _staff),
    const SizedBox(height: 12),
    Align(
      alignment: Alignment.centerLeft,
      child: FilledButton(key: const ValueKey('flash-save'), onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving...' : 'Save')),
    ),
  ]);
}
