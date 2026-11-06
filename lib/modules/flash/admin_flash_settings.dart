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
  late final _premium = TextEditingController(text: widget.config.helpPremium);
  late final _provider = TextEditingController(text: widget.config.helpProvider);
  late final _phone = TextEditingController(text: widget.config.supportPhone);
  late final _whatsapp = TextEditingController(text: widget.config.supportWhatsapp);
  bool _busy = false;

  @override
  void dispose() {
    for (final box in [_limit, _user, _vendor, _staff, _premium, _provider, _phone, _whatsapp]) {
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
      await widget.onSave({
        'dailyMessages': limit,
        'helpUser': _user.text,
        'helpVendor': _vendor.text,
        'helpStaff': _staff.text,
        'helpPremium': _premium.text,
        'helpProvider': _provider.text,
        'supportPhone': _phone.text.trim(),
        'supportWhatsapp': _whatsapp.text.trim(),
      });
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
    Text('Office phone and WhatsApp', style: Theme.of(context).textTheme.titleMedium),
    const Text('Paid vendors see these in their chat as "Call the office" and "WhatsApp the office".'),
    Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(key: const ValueKey('flash-support-phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Office phone number', hintText: '9876543210', border: OutlineInputBorder())),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        key: const ValueKey('flash-support-whatsapp'),
        controller: _whatsapp,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Office WhatsApp number', helperText: 'Leave empty to use the office phone number', border: OutlineInputBorder()),
      ),
    ),
    const SizedBox(height: 20),
    Text('Chat limit and help texts', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    TextField(
      key: const ValueKey('flash-limit'),
      controller: _limit,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Messages each person can send in a day', border: OutlineInputBorder()),
    ),
    const SizedBox(height: 12),
    const Text('What Flash knows about using the apps (FAQ answers, plan details, how-to). Plans, prices, items and areas are read live from the records, so changing them changes the answers. If a box is empty, Flash uses its built-in help for that app.'),
    _help('flash-help-user', 'User app help', _user),
    _help('flash-help-vendor', 'Vendor app help (free vendors)', _vendor),
    _help('flash-help-premium', 'Premium vendors: extra help', _premium),
    _help('flash-help-provider', 'Service providers help', _provider),
    _help('flash-help-staff', 'Staff app help', _staff),
    const SizedBox(height: 12),
    Align(
      alignment: Alignment.centerLeft,
      child: FilledButton(key: const ValueKey('flash-save'), onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving...' : 'Save')),
    ),
  ]);
}
