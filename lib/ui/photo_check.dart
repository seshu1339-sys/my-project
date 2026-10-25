import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/store.dart';

/// The photoChecks document id for a Storage path (functions/photo-check.js checkId).
String photoCheckId(String path) => path.split('/').join('~');

/// This month in India (YYYY-MM), the month the Google checks are counted in (functions/photo-check.js monthKey).
String photoCheckMonth([DateTime? now]) => (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 7);

/// What a Google check found, in words for the admin: the online result and the same photo used before.
List<(String, Color)> photoCheckLines(Map<String, dynamic> result) {
  const red = Color(0xFFB91C1C), orange = Color(0xFFB45309), green = Color(0xFF15803D), grey = Color(0xFF6B7280);
  final pages = (result['pages'] as List? ?? const []).length;
  return [
    switch (result['online']) {
      'none' => ('Google: not found online', green),
      'partial' => ('Google: similar pictures online${pages == 0 ? '' : ' ($pages page${pages == 1 ? '' : 's'})'}', orange),
      'full' => ('Google: this picture is online, probably copied${pages == 0 ? '' : ' ($pages page${pages == 1 ? '' : 's'})'}', red),
      'limit' => ('Google check not done: this month\'s free checks are used up', grey),
      _ => ('Google check could not run${'${result['note'] ?? ''}'.isEmpty ? '' : ': ${result['note']}'}', grey),
    },
    for (final d in (result['duplicates'] as List? ?? const []).cast<Map>())
      ('${d['exact'] == true ? 'Same file' : 'Same picture'} as ${_owner(d)}', red),
  ];
}

String _owner(Map d) => switch (d['kind']) {
  'staffAddition' => 'a staff addition (${d['label']})',
  'vendor' => 'a vendor\'s ${d['label']}',
  'vendorApplication' => 'a vendor application (${d['label']})',
  'provider' => 'a service provider\'s photo',
  'fieldSubmission' => 'a field entry',
  _ => '${d['path']}',
};

/// Under a photo the admin reviews: the "Google check" button, and what the check found.
class PhotoCheckView extends StatelessWidget {
  const PhotoCheckView({super.key, required this.path, required this.result, required this.busy, required this.onCheck, this.width = 200});
  final String path;
  final Map<String, dynamic>? result;
  final bool busy;
  final VoidCallback? onCheck;
  final double width;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final links = r == null ? const <Map>[] : (r['pages'] as List? ?? const []).cast<Map>();
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r != null)
            for (final (text, color) in photoCheckLines(r))
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
          for (final link in links.take(3))
            InkWell(
              onTap: () => launchUrl(Uri.parse('${link['url']}'), mode: LaunchMode.externalApplication),
              child: Text('${'${link['title'] ?? ''}'.isEmpty ? link['url'] : link['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
            ),
          if (r == null)
            OutlinedButton.icon(
              key: ValueKey('google-check-$path'),
              onPressed: busy ? null : onCheck,
              icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image_search, size: 18),
              label: const Text('Google check'),
            )
          else
            TextButton(key: ValueKey('google-check-again-$path'), onPressed: busy ? null : onCheck, child: Text(busy ? 'Checking...' : 'Check again')),
        ],
      ),
    );
  }
}

/// [PhotoCheckView] for one photo, with its saved result read live (photoChecks) and the check sent to the server (checkPhoto).
class PhotoCheck extends StatefulWidget {
  const PhotoCheck({super.key, required this.store, required this.path, this.width = 200});
  final Store store;
  final String path;
  final double width;
  @override
  State<PhotoCheck> createState() => _PhotoCheckState();
}

class _PhotoCheckState extends State<PhotoCheck> {
  bool busy = false;

  Future<void> _check() async {
    setState(() => busy = true);
    try {
      await widget.store.call('checkPhoto', {'path': widget.path});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: widget.store.firestore.collection('photoChecks').doc(photoCheckId(widget.path)).snapshots(),
    builder: (context, snapshot) => PhotoCheckView(path: widget.path, result: snapshot.data?.data(), busy: busy, onCheck: _check, width: widget.width),
  );
}

/// "Google checks this month: 37 of 1000" (photoCheckUsage), so the admin sees how much of the free allowance is left.
class PhotoCheckUsage extends StatelessWidget {
  const PhotoCheckUsage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('photoCheckUsage').doc(photoCheckMonth()).snapshots(),
    builder: (context, snapshot) => Text(photoCheckUsageText(snapshot.data?.data()), key: const ValueKey('photo-check-usage')),
  );
}

String photoCheckUsageText(Map<String, dynamic>? usage) {
  final scans = (usage?['scans'] as num?)?.toInt() ?? 0;
  final limit = (usage?['limit'] as num?)?.toInt() ?? 1000;
  return 'Google checks this month: $scans of $limit free';
}
