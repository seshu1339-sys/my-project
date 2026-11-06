import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'staff_link_model.dart';

/// Staff app > Add > Vendor (or Services): the staff member enters the ID the vendor or provider got when they registered themselves
/// in the vendor app. Within 30 minutes of that registration the person is linked to this staff member; after that it is refused.
class StaffLinkPage extends StatefulWidget {
  const StaffLinkPage({super.key, required this.store, required this.provider, this.onLink});
  final Store store;
  // true: a service provider (SRV-...); false: a vendor (VEN-...).
  final bool provider;
  // For tests: what linking does (the linkStaffRegistration callable by default).
  final Future<Map<String, dynamic>> Function(String code)? onLink;

  @override
  State<StaffLinkPage> createState() => _StaffLinkPageState();
}

class _StaffLinkPageState extends State<StaffLinkPage> {
  final code = TextEditingController();
  bool busy = false;
  String? error, done;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final value = code.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final prefix = widget.provider ? 'SRV-' : 'VEN-';
    if (!looksLikeAccountCode(value) || !value.startsWith(prefix)) {
      setState(() {
        error = 'Enter the ${widget.provider ? 'Provider' : 'Vendor'} ID, like ${widget.provider ? 'SRV-NRPM-116-001' : 'VEN-NRPM-116-325'}';
        done = null;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
      done = null;
    });
    try {
      final result = await (widget.onLink ?? (c) => widget.store.call('linkStaffRegistration', {'code': c}))(value);
      if (mounted) {
        setState(() {
          done = 'Linked: ${result['name'] ?? value} ($value) is now registered by you.';
          code.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.provider ? 'service provider' : 'vendor';
    final idName = widget.provider ? 'Provider ID' : 'Vendor ID';
    return Scaffold(
      appBar: AppBar(title: Text(widget.provider ? 'Link a service provider' : 'Link a vendor')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'The $who registers in the vendor app on their own phone. Then enter the $idName they got here, within 30 minutes of their registration, to link them to you. Only vendors inside your own area can be linked.',
              ),
              const SizedBox(height: 4),
              const Text('You only see whether they keep their items up to date. You cannot change their shop, items or prices.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('staff-link-code'),
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: idName, hintText: widget.provider ? 'SRV-NRPM-116-001' : 'VEN-NRPM-116-325', errorText: error),
                onSubmitted: (_) => busy ? null : _link(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('staff-link-save'),
                onPressed: busy ? null : _link,
                icon: const Icon(Icons.link),
                label: Text(busy ? 'Linking...' : 'Link'),
              ),
              if (done != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(done!, key: const ValueKey('staff-link-done'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
