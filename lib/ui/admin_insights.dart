import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';

/// Site and ad statistics, plus the price-drop alert audience and controls.
/// Reads the aggregates written by the trackEvent function and the interest
/// records the customer app already keeps; nothing here duplicates them.
class AdminInsightsPage extends StatefulWidget {
  const AdminInsightsPage({super.key, required this.store});
  final Store store;
  @override
  State<AdminInsightsPage> createState() => _AdminInsightsPageState();
}

num _n(Object? v) => v is num ? v : 0;
String _pct(num clicks, num impressions) => impressions <= 0 ? '0.0%' : '${(clicks * 100 / impressions).toStringAsFixed(1)}%';
String _when(Object? ms) => ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal().toString().substring(0, 16) : '—';

class _AdminInsightsPageState extends State<AdminInsightsPage> {
  int days = 30;
  Map<String, num> total = {}, period = {}, today = {};
  Map<String, Map<String, num>> ads = {};
  bool loading = true, sending = false;
  String? error, productId, notice;
  List<Map<String, dynamic>>? audience;
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    load();
  }

  Map<String, num> _sum(Iterable<Map<String, dynamic>> docs) {
    final out = <String, num>{};
    for (final d in docs) {
      d.forEach((k, v) { if (v is num) out[k] = (out[k] ?? 0) + v; });
    }
    return out;
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final now = DateTime.now().toUtc();
      final since = now.subtract(Duration(days: days - 1)).toIso8601String().substring(0, 10);
      final todayKey = now.toIso8601String().substring(0, 10);
      final db = store.firestore;
      final results = await Future.wait([
        db.collection('analyticsTotals').get(),
        db.collection('analyticsDaily').where('day', isGreaterThanOrEqualTo: since).get(),
        db.collection('analyticsAds').limit(1000).get(),
      ]);
      final daily = results[1].docs.map((d) => d.data()).toList();
      final perAd = <String, List<Map<String, dynamic>>>{};
      for (final d in results[2].docs) {
        perAd.putIfAbsent('${d.data()['adId'] ?? d.id.split('~').first}', () => []).add(d.data());
      }
      if (!mounted) return;
      setState(() {
        total = _sum(results[0].docs.map((d) => d.data()));
        period = _sum(daily);
        today = _sum(daily.where((d) => d['day'] == todayKey));
        ads = {for (final e in perAd.entries) e.key: {..._sum(e.value), 'placement': 0}};
        _placements = {for (final e in perAd.entries) e.key: e.value.map((d) => d['placement']).whereType<String>().firstOrNull ?? ''};
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = 'Statistics could not load. $e'; });
    }
  }

  Map<String, String> _placements = {};

  bool get autoOn => store.business.text('priceDropAutoEnabled', 'true').trim().toLowerCase() != 'false';

  Future<void> setAuto(bool on) async {
    try {
      await store.firestore.collection('settings').doc('business').set({'priceDropAutoEnabled': on ? 'true' : 'false'}, SetOptions(merge: true));
      if (mounted) setState(() => notice = on ? 'Automatic price-drop alerts are ON.' : 'Automatic price-drop alerts are OFF. Manual sending still works.');
    } catch (e) {
      if (mounted) setState(() => notice = 'Could not change the setting: $e');
    }
  }

  Future<void> loadAudience() async {
    if (productId == null) return;
    setState(() { loading = true; error = null; });
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('priceAlertAudience').call({'productId': productId});
      final rows = ((result.data as Map)['rows'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      if (mounted) setState(() { audience = rows; loading = false; });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = 'Customers could not load. $e'; });
    }
  }

  Future<void> sendAlerts() async {
    final eligible = (audience ?? []).where((r) => r['eligible'] == true && r['alreadyNotified'] != true).length;
    final ok = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Send price alert'),
      content: Text('$eligible eligible customer(s) will receive a push notification with the current price. Anyone already alerted at this price is skipped.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Send now'))],
    ));
    if (ok != true) return;
    setState(() => sending = true);
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('sendPriceDropAlerts').call({'productId': productId});
      final r = Map<String, dynamic>.from(result.data as Map);
      if (mounted) setState(() => notice = 'Alert sent to ${r['sent']} customer(s). Already notified: ${r['duplicate']}. Not eligible: ${r['ineligible']}.');
      await loadAudience();
    } catch (e) {
      if (mounted) setState(() => notice = 'Alert could not be sent: $e');
    }
    if (mounted) setState(() => sending = false);
  }

  Widget _tile(String label, String value) => SizedBox(width: 170, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 12)),
    const SizedBox(height: 6),
    Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
  ]))));

  String _adName(String id) {
    final e = store.entries('promotions').where((p) => p.id == id);
    return e.isEmpty ? id : e.first.text('name', id);
  }

  Widget _statistics() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Text('Site and ad statistics', style: Theme.of(context).textTheme.titleLarge),
      const Spacer(),
      SegmentedButton<int>(
        segments: const [ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 30, label: Text('30 days')), ButtonSegment(value: 90, label: Text('90 days'))],
        selected: {days},
        onSelectionChanged: (s) { days = s.first; load(); },
      ),
      IconButton(tooltip: 'Refresh statistics', onPressed: loading ? null : load, icon: const Icon(Icons.refresh)),
    ]),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      _tile('Visitors, all time (unique)', '${_n(total['visitors'])}'),
      _tile('Visitors today (unique)', '${_n(today['visitors'])}'),
      _tile('Visits, last $days days', '${_n(period['visits'])}'),
      _tile('Web / Android visits', '${_n(period['visitsWeb'])} / ${_n(period['visitsAndroid'])}'),
      _tile('People who viewed ads, all time', '${_n(total['adViewers'])}'),
      _tile('Ad impressions, last $days days', '${_n(period['adImpressions'])}'),
      _tile('Ad clicks, last $days days', '${_n(period['adClicks'])}'),
      _tile('Click-through rate (CTR)', _pct(_n(period['adClicks']), _n(period['adImpressions']))),
      _tile('Visits from ads, last $days days', '${_n(period['visitsFromAds'])}'),
    ]),
    const SizedBox(height: 16),
    Text('Per ad (all time)', style: Theme.of(context).textTheme.titleMedium),
    if (ads.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No ad activity recorded yet.')),
    for (final e in ads.entries) Card(child: ListTile(
      title: Text(_adName(e.key)),
      subtitle: Text('${_placements[e.key] ?? ''} • impressions ${_n(e.value['impressions'])} • unique viewers ${_n(e.value['uniqueViewers'])} • clicks ${_n(e.value['clicks'])} • unique clickers ${_n(e.value['uniqueClickers'])} • CTR ${_pct(_n(e.value['clicks']), _n(e.value['impressions']))} • visits from ad ${_n(e.value['visitsFromAds'])}'),
    )),
  ]);

  Widget _alerts() {
    final products = store.entries('products');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(container: true, child: Text('Price-drop alerts', style: Theme.of(context).textTheme.titleLarge)),
      const SizedBox(height: 4),
      Semantics(container: true, child: const Text('Customers are eligible when they viewed the product in the last 90 days, turned alerts on and have a registered device. Each customer is alerted once per price.')),
      SwitchListTile(
        title: const Text('Automatic price-drop alerts'),
        subtitle: const Text('When ON, a price drop alerts eligible customers by itself. Turn OFF to send only manually.'),
        value: autoOn, onChanged: setAuto,
      ),
      Semantics(container: true, explicitChildNodes: true, child: Row(children: [
        Expanded(child: DropdownButtonFormField<String>(
          initialValue: productId, isExpanded: true, decoration: const InputDecoration(labelText: 'Product'),
          items: [for (final p in products) DropdownMenuItem(value: p.id, child: Text(p.text('name', p.id), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() { productId = v; audience = null; }),
        )),
        const SizedBox(width: 12),
        FilledButton(onPressed: productId == null || loading ? null : loadAudience, child: const Text('Show interested customers')),
      ])),
      if (audience != null) ...[
        const SizedBox(height: 8),
        Text('${audience!.length} customer(s) viewed this product • ${audience!.where((r) => r['eligible'] == true).length} eligible'),
        for (final r in audience!) Card(child: ListTile(
          title: Text(('${r['email']}'.isEmpty ? '${r['uid']}' : '${r['email']}')),
          subtitle: Text('Viewed ${r['viewCount']}× • last ${_when(r['lastViewedAt'])} • pincode ${'${r['pincode']}'.isEmpty ? '—' : r['pincode']} • current price ${r['currentPrice'] ?? '—'} • alerts sent ${r['alertCount']}${r['alertedAt'] != null ? ' (last ${_when(r['alertedAt'])} at ${r['alertedPrice']})' : ''}'),
          trailing: Wrap(spacing: 4, children: [
            if (r['eligible'] == true && r['alreadyNotified'] != true) const Chip(label: Text('Will receive')),
            if (r['alreadyNotified'] == true) const Chip(label: Text('Already notified')),
            if (r['subscribed'] != true) const Chip(label: Text('Alerts off')),
            if (r['subscribed'] == true && (r['tokens'] ?? 0) == 0) const Chip(label: Text('No device')),
            if (r['recent'] != true) const Chip(label: Text('Interest expired')),
          ]),
        )),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: sending || !(audience!.any((r) => r['eligible'] == true && r['alreadyNotified'] != true)) ? null : sendAlerts,
          icon: const Icon(Icons.notifications_active), label: Text(sending ? 'Sending...' : 'Send price alert to eligible customers'),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Insights and price alerts')),
    body: ListenableBuilder(listenable: store, builder: (context, _) => ListView(padding: const EdgeInsets.all(20), children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (notice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(notice!)),
      _statistics(),
      const Divider(height: 40),
      _alerts(),
    ])),
  );
}
