import 'package:flutter/material.dart';

import '../data/store.dart';

/// Why someone reports (the same keys as REASONS in functions/modules/abuse-reports).
const reportReasons = <String, String>{
  'cheating': 'Cheating or fraud',
  'abuse': 'Rude or abusive',
  'fake': 'Fake items, photos or prices',
  'no_show': 'Did not come or did not deliver',
  'other': 'Something else',
};

/// A small "Report" button. [target] is what the server needs: {'kind': 'shop', 'shopId'} or {'kind': 'provider', 'listingId'} (a
/// customer), {'kind': 'customer', 'orderId'} (a vendor). Only people who really dealt with them can report, once (the server checks);
/// at the admin's number of reports the account is suspended for now and the admin decides (functions/modules/abuse-reports).
class ReportButton extends StatelessWidget {
  const ReportButton({super.key, required this.store, required this.target, required this.label, this.send});
  final Store store;
  final Map<String, dynamic> target;
  final String label;

  /// Test seam: sends the report (the reportAbuse function by default).
  final Future<void> Function(Map<String, dynamic> data)? send;

  Future<void> _report(BuildContext context) async {
    final result = await showDialog<(String, String)>(context: context, builder: (_) => _ReportDialog(label: label));
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = {...target, 'reason': result.$1, 'details': result.$2};
      if (send != null) {
        await send!(data);
      } else {
        await store.call('reportAbuse', data);
      }
      messenger.showSnackBar(const SnackBar(content: Text('Thank you. The Support Team will look at your report.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''))));
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: ValueKey('report-${target['kind']}'),
    onPressed: () => _report(context),
    icon: const Icon(Icons.flag_outlined, size: 18),
    label: Text(target['kind'] == 'customer' ? 'Report customer' : 'Report'),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.label});
  final String label;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String? reason;
  final details = TextEditingController();

  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Report ${widget.label}'),
    content: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Only report real problems. Many reports suspend the account until the Support Team checks it.'),
        RadioGroup<String>(
          groupValue: reason,
          onChanged: (v) => setState(() => reason = v),
          child: Column(children: [
            for (final e in reportReasons.entries) RadioListTile<String>(key: ValueKey('report-reason-${e.key}'), dense: true, value: e.key, title: Text(e.value)),
          ]),
        ),
        TextField(key: const ValueKey('report-details'), controller: details, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'What happened? (optional)')),
      ]),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const ValueKey('report-send'),
        onPressed: reason == null ? null : () => Navigator.pop(context, (reason!, details.text.trim())),
        child: const Text('Send report'),
      ),
    ],
  );
}
