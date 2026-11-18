import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/store.dart';
import 'company_messages_data.dart';

/// What the vendor's bell and inbox show: the messages for them and the ones they already opened.
class CompanyInboxData {
  const CompanyInboxData({this.messages = const [], this.read = const {}});
  final List<CompanyMessage> messages;
  final Set<String> read;
  int get unread => messages.where((m) => !read.contains(m.id)).length;
}

/// The vendor's own town and category: from their shop record.
Future<({String town, String category})> vendorPlace(Store store, String uid) async {
  var shop = store.entries('shops').where((s) => s.id == uid).firstOrNull?.data;
  if (shop == null && store.live) {
    try {
      shop = (await store.firestore.collection('shops').doc(uid).get()).data();
    } catch (_) {/* no shop yet */}
  }
  return (town: '${shop?['town'] ?? ''}', category: '${shop?['category'] ?? ''}');
}

/// Three reads: the everyone-list (one record), the messages sent to this vendor by ID, and their own read record.
Future<CompanyInboxData> loadCompanyInbox(Store store) async {
  final uid = store.user?.uid;
  if (!store.live || uid == null) return const CompanyInboxData();
  final db = store.firestore;
  final place = await vendorPlace(store, uid);
  final results = await Future.wait([
    db.collection('companyMessagesIndex').doc('vendors').get(),
    db.collection('companyMessages').where('vendorUids', arrayContains: uid).where('deleted', isEqualTo: false).orderBy('sentAt', descending: true).limit(30).get(),
    db.collection('companyMessageReads').doc(uid).get(),
  ]);
  final index = (results[0] as DocumentSnapshot<Map<String, dynamic>>).data();
  final everyone = [
    for (final e in (index?['items'] is List ? index!['items'] as List : const []))
      if (e is Map) CompanyMessage.from('${e['id']}', Map<String, dynamic>.from(e)),
  ];
  final mine = [for (final d in (results[1] as QuerySnapshot<Map<String, dynamic>>).docs) CompanyMessage.from(d.id, d.data())];
  final read = {for (final id in ((results[2] as DocumentSnapshot<Map<String, dynamic>>).data()?['read'] as List? ?? const [])) '$id'};
  _syncTopics(uid, place.town, place.category);
  return CompanyInboxData(messages: vendorInbox(everyone: everyone, mine: mine, town: place.town, category: place.category, now: DateTime.now()), read: read);
}

/// The free push: the app joins the topics of all vendors, its town, its category and itself; leaves the ones that no longer fit
/// (a new town or category). Android app only.
Future<void> _syncTopics(String uid, String town, String category) async {
  if (kIsWeb) return;
  try {
    final wanted = companyTopicsFor(uid: uid, town: town, category: category);
    final prefs = await SharedPreferences.getInstance();
    final had = prefs.getStringList('companyTopics') ?? const [];
    for (final t in wanted.where((t) => !had.contains(t))) {
      await FirebaseMessaging.instance.subscribeToTopic(t);
    }
    for (final t in had.where((t) => !wanted.contains(t))) {
      await FirebaseMessaging.instance.unsubscribeFromTopic(t);
    }
    await prefs.setStringList('companyTopics', wanted);
  } catch (_) {
    /* the inbox still works without the push */
  }
}

/// The bell at the top of the vendor app with the unread count. A tap (or a tapped push) opens the inbox.
class CompanyBell extends StatefulWidget {
  const CompanyBell({super.key, required this.store, this.load, this.markRead});
  final Store store;

  /// Test seams: what the inbox holds, and "these were opened".
  final Future<CompanyInboxData> Function()? load;
  final Future<void> Function(List<String> ids)? markRead;
  @override
  State<CompanyBell> createState() => _CompanyBellState();
}

class _CompanyBellState extends State<CompanyBell> {
  late Future<CompanyInboxData> data = _load();
  StreamSubscription<RemoteMessage>? _opened, _arrived;
  static bool _initialChecked = false;

  Future<CompanyInboxData> _load() => (widget.load ?? () => loadCompanyInbox(widget.store))().catchError((Object _) => const CompanyInboxData());

  @override
  void initState() {
    super.initState();
    if (widget.load == null && widget.store.live && !kIsWeb) {
      try {
        _opened = FirebaseMessaging.onMessageOpenedApp.listen((m) {
          if (m.data['type'] == 'company_message' && mounted) _open();
        });
        _arrived = FirebaseMessaging.onMessage.listen((m) {
          if (m.data['type'] == 'company_message' && mounted) setState(() => data = _load());
        });
        if (!_initialChecked) {
          _initialChecked = true;
          FirebaseMessaging.instance.getInitialMessage().then((m) {
            if (m?.data['type'] == 'company_message' && mounted) _open();
          }).catchError((Object _) {});
        }
      } catch (_) {/* no push on this device */}
    }
  }

  @override
  void dispose() {
    _opened?.cancel();
    _arrived?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    final inbox = await data;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CompanyInboxPage(store: widget.store, data: inbox, markRead: widget.markRead),
    ));
    if (mounted) setState(() => data = _load());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CompanyInboxData>(
    future: data,
    builder: (context, snap) {
      final unread = snap.data?.unread ?? 0;
      return IconButton(
        key: const ValueKey('company-bell'),
        tooltip: 'Messages from LOCAMARKET',
        onPressed: _open,
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread', key: const ValueKey('company-bell-count')),
          child: const Icon(Icons.notifications_outlined),
        ),
      );
    },
  );
}

/// All company messages for this vendor, newest first. Opening it counts the unread ones as read (once each).
class CompanyInboxPage extends StatefulWidget {
  const CompanyInboxPage({super.key, required this.store, required this.data, this.markRead});
  final Store store;
  final CompanyInboxData data;
  final Future<void> Function(List<String> ids)? markRead;
  @override
  State<CompanyInboxPage> createState() => _CompanyInboxPageState();
}

class _CompanyInboxPageState extends State<CompanyInboxPage> {
  @override
  void initState() {
    super.initState();
    final unread = [for (final m in widget.data.messages) if (!widget.data.read.contains(m.id)) m.id];
    if (unread.isNotEmpty) {
      final mark = widget.markRead ?? (ids) => widget.store.call('readCompanyMessages', {'ids': ids});
      unawaited(mark(unread.take(50).toList()).catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Messages from LOCAMARKET')),
    body: widget.data.messages.isEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No messages from the LOCAMARKET Team yet.')))
        : ListView(
            key: const ValueKey('company-inbox'),
            padding: const EdgeInsets.all(12),
            children: [
              for (final m in widget.data.messages)
                CompanyMessageCard(store: widget.store, message: m, unread: !widget.data.read.contains(m.id)),
            ],
          ),
  );
}

/// One message: the official badge, its type, date and time, "edited", the payment box and the photo.
class CompanyMessageCard extends StatelessWidget {
  const CompanyMessageCard({super.key, required this.store, required this.message, this.unread = false});
  final Store store;
  final CompanyMessage message;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return Card(
      key: ValueKey('company-message-${m.id}'),
      color: unread ? const Color(0xFFFFF8E1) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Chip(
              key: const ValueKey('company-badge'),
              avatar: const Icon(Icons.verified, size: 16, color: Color(0xFF1565C0)),
              label: const Text('LOCAMARKET Team', style: TextStyle(fontWeight: FontWeight.w700)),
              visualDensity: VisualDensity.compact,
              backgroundColor: const Color(0xFFE3F2FD),
            ),
            Chip(label: Text(m.typeLabel), visualDensity: VisualDensity.compact),
            if (m.edited) const Text('edited', key: ValueKey('company-edited'), style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
          ]),
          Text(companyTime(m.sentAt), style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(m.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(m.body),
          if (m.type == 'payment')
            Container(
              key: const ValueKey('company-payment-box'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFB74D)), borderRadius: BorderRadius.circular(8)),
              child: Text('Old amount: ${rupees(m.oldAmount)}  →  New amount: ${rupees(m.newAmount)}\nStarts on: ${companyDay(m.startsOn)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (m.hasPhoto) CompanyMessagePhoto(store: store, id: m.id),
        ]),
      ),
    );
  }
}

/// The message's photo (one read, only when the message has one).
class CompanyMessagePhoto extends StatelessWidget {
  const CompanyMessagePhoto({super.key, required this.store, required this.id});
  final Store store;
  final String id;

  @override
  Widget build(BuildContext context) => !store.live
      ? const SizedBox.shrink()
      : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: store.firestore.collection('companyMessagePhotos').doc(id).get(),
          builder: (context, snap) {
            final data = '${snap.data?.data()?['data'] ?? ''}';
            if (data.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: Image.memory(base64Decode(data), fit: BoxFit.contain)),
            );
          },
        );
}
