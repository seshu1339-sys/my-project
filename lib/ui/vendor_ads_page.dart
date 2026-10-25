import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/ad_reports.dart';
import '../domain/ads.dart';
import '../domain/ads_admin.dart';
import '../domain/catalog.dart';
import 'ad_box.dart';
import 'ad_reports_page.dart';
import 'ads_column.dart';
import 'shared.dart';
import 'screen_view.dart';

/// How long a vendor can run an ad for, with the plan each length goes with. The admin can still change plan and dates when approving.
const vendorAdDurations = <int, String>{7: '1 week', 15: '15 days', 30: '1 month', 60: '2 months'};

/// What the vendor is told about one of their ads: Pending approval / Live / Scheduled / Expired / Rejected / Switched off.
String vendorAdState(Entry ad, DateTime now) => adStatusLabels[adStatus(ad, now)] ?? 'Live';

/// "12 days left", "ends today", "ended 3 days ago", or '' with no end date.
String daysRemainingText(Entry ad, DateTime now) {
  final end = DateTime.tryParse(ad.text('endsAt'));
  if (end == null) return '';
  final left = end.difference(now);
  if (left.isNegative) return 'ended ${(-left.inDays).clamp(0, 9999)} day(s) ago';
  if (left.inHours < 24) return 'ends today';
  return '${(left.inHours / 24).ceil()} days left';
}

/// The vendor app's "My Ads": the ads they sent, with their state (nothing is live until the admin approves), days left and the live counts,
/// a form to send a new ad, a way to change a photo or text (which also waits for approval), and the daily / weekly summary choice.
class VendorAdsPage extends StatefulWidget {
  const VendorAdsPage({super.key, required this.store, required this.uid, this.now, this.call});
  final Store store;
  final String uid;
  final DateTime? now;
  // How requests reach the server (a Cloud Function call); replaced in tests.
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)? call;
  @override
  State<VendorAdsPage> createState() => _VendorAdsPageState();
}

class _VendorAdsPageState extends State<VendorAdsPage> {
  Store get store => widget.store;
  DateTime get now => widget.now ?? DateTime.now();

  void toast(Object m) => message(context, m);

  Future<void> _editor([Entry? ad]) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => VendorAdEditor(store: store, uid: widget.uid, ad: ad, call: widget.call)));
  }

  Future<void> _summary(Entry ad, String mode) async {
    try {
      await (widget.call ?? store.call)('setAdSummary', {'adId': ad.id, 'mode': mode});
      toast(mode == 'off' ? 'Summary switched off.' : 'You will get a $mode summary for this ad.');
    } catch (e) {
      toast(e);
    }
  }

  @override
  Widget build(BuildContext context) => ScreenView('vendor_my_ads', child: _page(context));

  Widget _page(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Ads')),
    floatingActionButton: FloatingActionButton.extended(key: const ValueKey('my-ad-new'), onPressed: _editor, icon: const Icon(Icons.add), label: const Text('New ad')),
    body: StreamBuilder<List<Entry>>(
      stream: store.watchEntries('adSubmissions', vendorId: widget.uid),
      builder: (context, subs) => StreamBuilder<List<Entry>>(
        stream: store.watchEntries('adStats', vendorId: widget.uid),
        builder: (context, stats) => StreamBuilder<List<Entry>>(
          stream: store.watchEntries('vendorNotices', vendorId: widget.uid),
          builder: (context, notices) => ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final mine = [for (final a in store.entries('ads')) if (a.text('vendorId') == widget.uid) a];
              final submissions = [for (final s in subs.data ?? const <Entry>[]) if (s.text('status') != 'approved') s];
              final statById = {for (final s in stats.data ?? const <Entry>[]) s.id: s};
              final recent = [...?notices.data]..sort((a, b) => '${b.data['createdAt']}'.compareTo('${a.data['createdAt']}'));
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  const Text('Nothing you send goes live by itself. The administrator checks every new ad and every change before customers see it.'),
                  const SizedBox(height: 8),
                  if (recent.isNotEmpty)
                    Card(
                      key: const ValueKey('my-ad-notices'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('Messages', style: TextStyle(fontWeight: FontWeight.bold))),
                        for (final n in recent.take(5)) ListTile(dense: true, title: Text(n.text('title')), subtitle: Text(n.text('body'))),
                      ]),
                    ),
                  if (submissions.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.only(top: 12, bottom: 4), child: Text('Waiting for the administrator', style: TextStyle(fontWeight: FontWeight.bold))),
                    for (final s in submissions)
                      Card(
                        key: ValueKey('my-sub-${s.id}'),
                        child: ListTile(
                          title: Text(s.text('title', '(picture only)')),
                          subtitle: Text(s.text('status') == 'rejected'
                              ? 'Rejected: ${s.text('reason')}'
                              : s.text('kind') == 'change' ? 'Pending approval — the change to your live ad. The old picture stays until it is approved.' : 'Pending approval'),
                          leading: Icon(s.text('status') == 'rejected' ? Icons.cancel_outlined : Icons.hourglass_top),
                        ),
                      ),
                  ],
                  const Padding(padding: EdgeInsets.only(top: 12, bottom: 4), child: Text('My ads', style: TextStyle(fontWeight: FontWeight.bold))),
                  if (mine.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('You have no ads yet. Tap "New ad" to send one.')),
                  for (final ad in mine) _adCard(ad, statById[ad.id], submissions.any((s) => s.text('adId') == ad.id && s.text('status') == 'pending')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('my-ad-report'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AdReportsPage(store: store, vendorId: widget.uid))),
                    icon: const Icon(Icons.bar_chart),
                    label: const Text('Daily numbers'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _adCard(Entry ad, Entry? stat, bool changePending) {
    final config = AdsConfig.from(store.entries('settings'));
    final totals = AdTotals()..add(stat?.data ?? const {});
    final state = vendorAdState(ad, now);
    return Card(
      key: ValueKey('my-ad-${ad.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 150, child: AdBox(ad: ad, config: config)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(ad.text('title', '(picture only)'), style: const TextStyle(fontWeight: FontWeight.bold))),
              Chip(label: Text(state, key: ValueKey('my-ad-state-${ad.id}'))),
            ]),
            if (ad.text('status') == 'rejected' && ad.text('reason').isNotEmpty) Text('Reason: ${ad.text('reason')}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Text(daysRemainingText(ad, now), key: ValueKey('my-ad-days-${ad.id}')),
            const SizedBox(height: 4),
            Wrap(spacing: 16, key: ValueKey('my-ad-stats-${ad.id}'), children: [
              Text('Views: ${totals.views}'),
              Text('People: ${totals.unique}'),
              Text('Taps: ${totals.taps}'),
              Text('Seconds on screen: ${totals.seconds}'),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                key: ValueKey('my-ad-change-${ad.id}'),
                onPressed: changePending ? null : () => _editor(ad),
                icon: const Icon(Icons.edit_outlined),
                label: Text(changePending ? 'Change waiting for approval' : 'Change picture or text'),
              ),
              DropdownButton<String>(
                key: ValueKey('my-ad-summary-${ad.id}'),
                value: ad.text('summary', 'off'),
                hint: const Text('Summary'),
                items: const [
                  DropdownMenuItem(value: 'off', child: Text('No summary')),
                  DropdownMenuItem(value: 'daily', child: Text('Daily summary')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly summary')),
                ],
                onChanged: (v) => v == null ? null : _summary(ad, v),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Send a new ad, or a change to one of the vendor's ads: picture (shown fitted to the ad box), optional text, plan and length. It goes to the
/// administrator as "Pending approval".
class VendorAdEditor extends StatefulWidget {
  const VendorAdEditor({super.key, required this.store, required this.uid, this.ad, this.call});
  final Store store;
  final String uid;
  final Entry? ad;
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)? call;
  @override
  State<VendorAdEditor> createState() => _VendorAdEditorState();
}

class _VendorAdEditorState extends State<VendorAdEditor> {
  late String contentType = widget.ad?.text('contentType', 'image') ?? 'image';
  late String imageUrl = widget.ad?.text('imageUrl') ?? '';
  late final title = TextEditingController(text: widget.ad?.text('title') ?? '');
  late final body = TextEditingController(text: widget.ad?.text('text') ?? '');
  late final phone = TextEditingController(text: widget.ad?.text('tapAction') == 'call' || widget.ad?.text('tapAction') == 'whatsapp' ? widget.ad!.text('tapValue') : '');
  late String tapAction = widget.ad?.text('tapAction') ?? '';
  String package = 'normal';
  int days = 30;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() => busy = true);
      final url = await widget.store.upload(file, folder: 'vendorProducts/${widget.uid}');
      if (mounted) setState(() => imageUrl = url);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Entry get preview => Entry('preview', {'contentType': contentType, 'imageUrl': imageUrl, 'title': title.text, 'text': body.text});

  Future<void> _send() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await (widget.call ?? widget.store.call)('submitVendorAd', {
        if (widget.ad != null) 'adId': widget.ad!.id,
        'contentType': contentType,
        'imageUrl': imageUrl,
        'title': title.text.trim(),
        'text': body.text.trim(),
        'tapAction': tapAction,
        'tapValue': tapAction.isEmpty ? '' : phone.text.trim(),
        'package': package,
        'durationDays': days,
      });
      if (mounted) {
        message(context, result['status'] == 'pending' ? 'Sent. It goes live only after the administrator approves it.' : 'Sent.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst(RegExp(r'^\[.*?\]\s*'), ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = AdsConfig.from(widget.store.entries('settings'));
    final height = adBoxHeight(config, MediaQuery.sizeOf(context).height, config.desktopSlots);
    return Scaffold(
      appBar: AppBar(title: Text(widget.ad == null ? 'New ad' : 'Change my ad')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('The administrator checks it first. Until then, customers keep seeing your approved ad as it is.'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: const ValueKey('vad-type'),
            segments: const [
              ButtonSegment(value: 'image', label: Text('Picture')),
              ButtonSegment(value: 'text', label: Text('Text')),
              ButtonSegment(value: 'imageText', label: Text('Both')),
            ],
            selected: {contentType},
            onSelectionChanged: (v) => setState(() => contentType = v.first),
          ),
          if (contentType != 'text') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(key: const ValueKey('vad-photo'), onPressed: busy ? null : _pick, icon: const Icon(Icons.upload), label: Text(imageUrl.isEmpty ? 'Choose a picture' : 'Choose another picture')),
          ],
          if (contentType != 'image') ...[
            const SizedBox(height: 8),
            TextField(key: const ValueKey('vad-title'), controller: title, onChanged: (_) => setState(() {}), maxLength: 80, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
            TextField(key: const ValueKey('vad-text'), controller: body, onChanged: (_) => setState(() {}), maxLength: 300, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Small text (optional)', border: OutlineInputBorder())),
          ],
          const SizedBox(height: 8),
          const Text('How it will look (the picture is cropped to fill the box):', style: TextStyle(fontSize: 12)),
          Align(alignment: Alignment.centerLeft, child: SizedBox(key: const ValueKey('vad-preview'), width: 300, height: height, child: AdBox(ad: preview, config: config))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('vad-tap'),
            initialValue: tapAction,
            decoration: const InputDecoration(labelText: 'When a customer taps it', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: '', child: Text('Nothing')),
              DropdownMenuItem(value: 'call', child: Text('Call me')),
              DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp me')),
            ],
            onChanged: (v) => setState(() => tapAction = v ?? ''),
          ),
          if (tapAction.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: TextField(key: const ValueKey('vad-phone'), controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Your phone number', border: OutlineInputBorder()))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const ValueKey('vad-package'),
                initialValue: package,
                decoration: const InputDecoration(labelText: 'Plan', border: OutlineInputBorder()),
                items: [for (final e in adPackages.entries) DropdownMenuItem(value: e.key, child: Text('${e.value} (${adPackageDefaults[e.key]!.rounds}x each round)'))],
                onChanged: (v) => setState(() => package = v ?? 'normal'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: const ValueKey('vad-days'),
                initialValue: days,
                decoration: const InputDecoration(labelText: 'Runs for', border: OutlineInputBorder()),
                items: [for (final e in vendorAdDurations.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => days = v ?? 30),
              ),
            ),
          ]),
          if (widget.ad != null) const Padding(padding: EdgeInsets.only(top: 4), child: Text('The plan and length only apply to a new ad; the administrator keeps your current dates.', style: TextStyle(fontSize: 12))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, key: const ValueKey('vad-error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(key: const ValueKey('vad-send'), onPressed: busy ? null : _send, child: Text(busy ? 'Please wait…' : 'Send for approval')),
        ],
      ),
    );
  }
}
