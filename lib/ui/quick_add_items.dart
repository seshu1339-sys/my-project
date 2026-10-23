import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/quick_items.dart';
import 'quick_add_core.dart';
import 'quick_add_item.dart';

/// "My Items": Scheduled / Live / Expired, with Edit, Cancel and Re-activate.
class QuickMyItemsPage extends StatelessWidget {
  const QuickMyItemsPage({super.key, required this.store, required this.account, this.stream, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final QuickEnv env;
  // Test seam.
  final Stream<List<Entry>>? stream;

  Stream<List<Entry>> _items() =>
      stream ??
      store.firestore.collection('quickItems').where('ownerUid', isEqualTo: account.id).snapshots().map(
        (s) => s.docs.map((d) => Entry(d.id, d.data())).toList(),
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('My Items'),
        bottom: const TabBar(tabs: [Tab(text: 'Scheduled'), Tab(text: 'Live'), Tab(text: 'Expired')]),
      ),
      body: StreamBuilder<List<Entry>>(
        stream: _items(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Items could not load.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return QuickItemTabs(items: snapshot.data!, store: store, account: account, env: env);
        },
      ),
    ),
  );
}

/// The three lists, re-evaluated every 30 seconds so an item moves from Scheduled to Live to
/// Expired on its own.
class QuickItemTabs extends StatefulWidget {
  const QuickItemTabs({super.key, required this.items, required this.store, required this.account, this.env = const QuickEnv(), this.now});
  final List<Entry> items;
  final Store store;
  final Entry account;
  final QuickEnv env;
  final DateTime Function()? now;
  @override
  State<QuickItemTabs> createState() => _QuickItemTabsState();
}

class _QuickItemTabsState extends State<QuickItemTabs> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime get now => (widget.now ?? DateTime.now)();
  bool get isVendor => widget.account.text('role') == 'vendor';

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String function, Map<String, dynamic> data, String done) async {
    try {
      await widget.env.run(widget.store, function, data);
      _say(done);
    } catch (e) {
      _say(quickCleanError(e));
    }
  }

  Future<void> _reactivate(Entry item) async {
    final timing = QuickTiming(durationUnit: item.text('durationUnit', 'hours'), durationValue: item.number('durationValue', 2).round());
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Show this item again'),
        content: SingleChildScrollView(child: QuickTimingFields(timing: timing)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Back')),
          FilledButton(key: const ValueKey('quick-reactivate-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Send to admin')),
        ],
      ),
    );
    if (ok != true) return;
    if (timing.startMode == 'schedule' && timing.scheduleAt == null) {
      _say('Pick the date and time to start.');
      return;
    }
    QuickFix? fix;
    if (isVendor) {
      try {
        fix = await widget.env.fix();
      } catch (e) {
        _say(quickCleanError(e));
        return;
      }
      final metres = quickMetresFromShop(widget.account, fix);
      if (metres == null || metres > quickShopRadiusMetres) {
        _say(quickNotAtShop);
        return;
      }
    }
    await _run(
      'reactivateQuickItem',
      {'itemId': item.id, ...timing.toPayload(), if (fix != null) 'latitude': fix.latitude, if (fix != null) 'longitude': fix.longitude},
      'Sent to the admin for approval.',
    );
  }

  void _edit(Entry item) {
    final category = widget.store.entries('categories').where((c) => c.id == item.text('categoryId')).firstOrNull ??
        Entry(item.text('categoryId'), {'name': item.text('categoryName')});
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuickItemFormPage(store: widget.store, account: widget.account, category: category, editing: item, env: widget.env),
      ),
    );
  }

  String _status(Entry item, QuickPhase phase) {
    switch (phase) {
      case QuickPhase.pending:
        return 'Waiting for admin approval';
      case QuickPhase.scheduled:
        return 'Starts ${quickDateTimeLabel(quickStartsAt(item)!)}';
      case QuickPhase.live:
        return 'Available for ${quickCountdown(quickExpiresAt(item)!.difference(now))}';
      case QuickPhase.expired:
        return 'Ended ${quickDateTimeLabel(quickExpiresAt(item) ?? now)}';
      case QuickPhase.rejected:
        final reason = item.text('decisionReason');
        return 'Rejected${reason.isEmpty ? '' : ': $reason'}';
      case QuickPhase.cancelled:
        return 'Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final byTab = {for (final tab in QuickTab.values) tab: <Entry>[]};
    for (final item in widget.items) {
      byTab[quickTabOf(quickPhase(item, now))]!.add(item);
    }
    for (final list in byTab.values) {
      list.sort((a, b) => b.id.compareTo(a.id));
    }
    return TabBarView(
      children: [
        for (final tab in QuickTab.values)
          byTab[tab]!.isEmpty
              ? Center(key: ValueKey('quick-empty-${tab.name}'), child: Text('No ${tab.name} items.'))
              : ListView(
                  key: ValueKey('quick-list-${tab.name}'),
                  padding: const EdgeInsets.all(12),
                  children: [for (final item in byTab[tab]!) _tile(item)],
                ),
      ],
    );
  }

  Widget _tile(Entry item) {
    final phase = quickPhase(item, now);
    final canCancel = {QuickPhase.pending, QuickPhase.scheduled, QuickPhase.live}.contains(phase);
    final canReactivate = {QuickPhase.expired, QuickPhase.cancelled, QuickPhase.rejected}.contains(phase);
    return Card(
      key: ValueKey('quick-item-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              QuickItemPhoto(store: widget.store, item: item, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.text('name'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('₹${_money(item.number('price'))} ${item.text('unit')} • ${item.text('locationName')}'),
                    Text(item.text('categoryName'), style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(_status(item, phase), key: ValueKey('quick-status-${item.id}'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                key: ValueKey('quick-edit-${item.id}'),
                onPressed: () => _edit(item),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              if (canCancel)
                OutlinedButton.icon(
                  key: ValueKey('quick-cancel-${item.id}'),
                  onPressed: () => _run('cancelQuickItem', {'itemId': item.id}, 'Cancelled.'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
              if (canReactivate)
                FilledButton.icon(
                  key: ValueKey('quick-reactivate-${item.id}'),
                  onPressed: () => _reactivate(item),
                  icon: const Icon(Icons.replay),
                  label: const Text('Re-activate'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

String _money(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

// Download links of private photos, looked up once per path.
final _storageUrls = <String, Future<String>>{};

/// The item's photo: the public one once approved, else the owner's private upload.
class QuickItemPhoto extends StatelessWidget {
  const QuickItemPhoto({super.key, required this.store, required this.item, this.size = 64});
  final Store store;
  final Entry item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = item.text('imageUrl');
    Widget box(Widget child) => ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: size, height: size, child: child));
    const placeholder = ColoredBox(color: Colors.black12, child: Icon(Icons.image_outlined));
    if (url.isNotEmpty) return box(Image.network(url, fit: BoxFit.cover, errorBuilder: (_, e, s) => placeholder));
    final path = item.text('photoPath');
    if (!store.live || path.isEmpty) return box(placeholder);
    return box(
      FutureBuilder<String>(
        future: _storageUrls.putIfAbsent(path, () => FirebaseStorage.instance.ref(path).getDownloadURL()),
        builder: (context, snapshot) => snapshot.hasData
            ? Image.network(snapshot.data!, fit: BoxFit.cover, errorBuilder: (_, e, s) => placeholder)
            : placeholder,
      ),
    );
  }
}
