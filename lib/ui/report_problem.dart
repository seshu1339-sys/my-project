import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../services/app_monitoring.dart';
import '../services/photo_compress.dart';

/// "Report a problem" in the Vendor, Staff and User apps (owner spec G, 17 Nov 2026): the person writes what went wrong and may add a
/// screenshot; it reaches the admin's App Health page (functions/modules/app-problems reportProblem) with the app, version, device and
/// screen, and the Vendor / Staff ID when signed in. The screenshot is made small on the phone (under 400 KB) before it is sent.
class ReportProblemButton extends StatelessWidget {
  const ReportProblemButton({super.key, required this.store, this.asIcon = false, this.send});
  final Store store;

  /// An icon for an app bar; otherwise a text button.
  final bool asIcon;

  /// Test seam: the server call.
  final Future<void> Function(Map<String, Object?> data)? send;

  Future<void> _open(BuildContext context) => showDialog<void>(context: context, builder: (_) => ReportProblemDialog(store: store, send: send));

  @override
  Widget build(BuildContext context) => asIcon
      ? IconButton(key: const ValueKey('report-problem'), tooltip: 'Report a problem', onPressed: () => _open(context), icon: const Icon(Icons.bug_report_outlined))
      : OutlinedButton.icon(key: const ValueKey('report-problem'), onPressed: () => _open(context), icon: const Icon(Icons.bug_report_outlined), label: const Text('Report a problem'));
}

class ReportProblemDialog extends StatefulWidget {
  const ReportProblemDialog({super.key, required this.store, this.send});
  final Store store;
  final Future<void> Function(Map<String, Object?> data)? send;
  @override
  State<ReportProblemDialog> createState() => _ReportProblemDialogState();
}

class _ReportProblemDialogState extends State<ReportProblemDialog> {
  final text = TextEditingController();
  String? screenshot; // base64
  String? error;
  bool busy = false, sent = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final small = await shrinkPhotoInBackground(await file.readAsBytes());
      if (small == null) return setState(() => error = 'That file is not a photo.');
      if (small.length > 400 * 1024) return setState(() => error = 'The screenshot is too big. Try another one.');
      setState(() { screenshot = base64Encode(small); error = null; });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _send() async {
    if (text.text.trim().isEmpty) return setState(() => error = 'Write what went wrong.');
    setState(() { busy = true; error = null; });
    final data = {...AppMonitoring.reportHeader(), 'text': text.text.trim(), 'screenshot': ?screenshot};
    try {
      await (widget.send ?? (d) => widget.store.call('reportProblem', d))(data);
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').replaceFirst('Bad state: ', ''));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report a problem'),
    content: sent
        ? const Text('Thank you. The LOCAMARKET team will look at it.', key: ValueKey('report-problem-sent'))
        : SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                key: const ValueKey('report-problem-text'),
                controller: text,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'What went wrong? (Telugu or English)', border: OutlineInputBorder()),
              ),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                TextButton.icon(onPressed: busy ? null : _pick, icon: const Icon(Icons.image_outlined), label: Text(screenshot == null ? 'Add a screenshot (optional)' : 'Screenshot added')),
                if (screenshot != null) IconButton(tooltip: 'Remove', onPressed: () => setState(() => screenshot = null), icon: const Icon(Icons.close)),
              ]),
              if (error != null) Text(error!, key: const ValueKey('report-problem-error'), style: const TextStyle(color: Colors.red)),
            ]),
          ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(sent ? 'Close' : 'Cancel')),
      if (!sent) FilledButton(key: const ValueKey('report-problem-send'), onPressed: busy ? null : _send, child: Text(busy ? 'Sending…' : 'Send')),
    ],
  );
}
