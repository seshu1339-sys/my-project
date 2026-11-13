import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/store.dart';
import 'photo_allowance.dart';

/// Vendor app: the photo of each item. Our standard photo, or the vendor's own (camera or gallery), which the admin checks first and
/// which counts toward the extra photos. An item of a category that needs an own photo (for example sarees) stays hidden until its own
/// photo is approved. Changing a photo replaces the old one (the old file is deleted).
///
/// Owner, 7 Nov 2026: the vendor also chooses how long each item shows in the website's category and search results (1 week to 3
/// months; asked when sending an own photo, and any time from the item's menu). An item showing in one of the vendor's Today's Offers
/// boxes is marked live in its own colour.
class ItemPhotosSection extends StatefulWidget {
  const ItemPhotosSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  State<ItemPhotosSection> createState() => _ItemPhotosSectionState();
}

class _ItemPhotosSectionState extends State<ItemPhotosSection> {
  String? busy;

  Future<void> _own(String productId, ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (file == null || !mounted) return;
    final days = await showDialog<int>(context: context, builder: (_) => const SearchTimeDialog());
    if (days == null) return;
    setState(() => busy = productId);
    try {
      final bytes = await file.readAsBytes();
      await FirebaseStorage.instance.ref('vendorItemPhotos/${widget.uid}/$productId').putData(bytes, SettableMetadata(contentType: 'image/jpeg', cacheControl: 'no-cache'));
      final result = await widget.store.call('submitItemPhoto', {'productId': productId, 'searchDays': days});
      // The photo is checked automatically (functions/photo-safety.js): approved at once, or the admin checks it when the check cannot run.
      messenger.showSnackBar(SnackBar(content: Text(result['status'] == 'approved' ? 'Checked: your photo is live now.' : 'Sent. The photo shows once the admin has checked it.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = null);
  }

  Future<void> _searchTime(String productId) async {
    final messenger = ScaffoldMessenger.of(context);
    final days = await showDialog<int>(context: context, builder: (_) => const SearchTimeDialog());
    if (days == null || !mounted) return;
    setState(() => busy = productId);
    try {
      await widget.store.call('setItemSearchTime', {'productId': productId, 'days': days});
      messenger.showSnackBar(SnackBar(content: Text('The item shows in search for ${searchTimeChoices[days]}.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = null);
  }

  Future<void> _ours(String productId) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = productId);
    try {
      await widget.store.call('removeItemPhoto', {'productId': productId});
      messenger.showSnackBar(const SnackBar(content: Text('The item uses our photo again.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = null);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PhotoAllowance>(
    stream: watchPhotoAllowance(widget.store, widget.uid),
    builder: (context, allowance) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.store.firestore.collection('products').where('ownerId', isEqualTo: widget.uid).snapshots(),
      builder: (context, products) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // The vendor's own Today's Offers boxes (functions/modules/todays-offer), read here only to mark the items that are live in one.
        stream: widget.store.firestore.collection('vendorTodaysOffers').where('vendorId', isEqualTo: widget.uid).snapshots(),
        builder: (context, offers) => ItemPhotosView(
          allowance: allowance.data,
          items: [for (final d in products.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) (d.id, d.data())],
          inTodaysOffers: {
            for (final d in offers.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (d.data()['endsAt'] case final Timestamp end when end.toDate().isAfter(DateTime.now()) && '${d.data()['productId'] ?? ''}'.isNotEmpty)
                '${d.data()['productId']}': end.toDate(),
          },
          busy: busy,
          onCamera: (id) => _own(id, ImageSource.camera),
          onGallery: (id) => _own(id, ImageSource.gallery),
          onOurs: _ours,
          onSearchTime: _searchTime,
        ),
      ),
    ),
  );
}

/// How long an item may show in search, in days, with the words the vendor reads (functions/modules/photo-limits SEARCH_DAYS).
const searchTimeChoices = <int, String>{7: '1 week', 30: '1 month', 60: '2 months', 90: '3 months'};

/// The colour an item live in Today's Offers is marked in (the same as the vendor's Today's Offers boxes).
const todaysOfferLiveColour = Color(0xFFE65100);

/// Asks how long an item shows in the website's category and search results. Pops the days, or null when cancelled.
class SearchTimeDialog extends StatefulWidget {
  const SearchTimeDialog({super.key});

  @override
  State<SearchTimeDialog> createState() => _SearchTimeDialogState();
}

class _SearchTimeDialogState extends State<SearchTimeDialog> {
  int days = 30;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('How long should this item show in search?'),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Customers find it on the website and in the app under its category (for example sarees under Sarees) and when they search.'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final c in searchTimeChoices.entries)
          ChoiceChip(key: ValueKey('search-time-${c.key}'), label: Text(c.value), selected: days == c.key, onSelected: (_) => setState(() => days = c.key)),
      ]),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('search-time-save'), onPressed: () => Navigator.pop(context, days), child: const Text('OK')),
    ],
  );
}

String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

class ItemPhotosView extends StatelessWidget {
  const ItemPhotosView({
    super.key,
    required this.allowance,
    required this.items,
    this.busy,
    required this.onCamera,
    required this.onGallery,
    required this.onOurs,
    this.onSearchTime,
    this.inTodaysOffers = const {},
    this.now,
  });
  final PhotoAllowance? allowance;
  final List<(String, Map<String, dynamic>)> items;
  final String? busy;
  final void Function(String productId) onCamera, onGallery, onOurs;
  final void Function(String productId)? onSearchTime;
  // The items live in one of the vendor's Today's Offers boxes, with when the box ends.
  final Map<String, DateTime> inTodaysOffers;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final a = allowance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Item photos', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('Each item can use our standard photo, or your own. Your own photos are checked by the admin and count toward your extra photos. You choose how long each item shows in search.'),
          if (a != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Extra photos used: ${a.used} of ${a.extras}${a.paid ? '' : ' (free plan)'} • your shop photo is not counted', key: const ValueKey('photo-allowance'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (items.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Add an item first.')),
          for (final (id, item) in items)
            ListTile(
              key: ValueKey('item-photo-$id'),
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 48,
                height: 48,
                child: '${item['imageUrl'] ?? ''}'.isEmpty ? const Icon(Icons.image_outlined) : Image.network('${item['imageUrl']}', fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_outlined)),
              ),
              title: Text('${item['name'] ?? ''}'),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_status(item), style: TextStyle(color: item['awaitingOwnPhoto'] == true ? Theme.of(context).colorScheme.error : null)),
                if (_search(item) case (final String text, final bool out))
                  Text(text, key: ValueKey('item-search-$id'), style: TextStyle(fontSize: 12, color: out ? Theme.of(context).colorScheme.error : null)),
                if (inTodaysOffers[id] case final end?)
                  Container(
                    key: ValueKey('item-live-offer-$id'),
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: todaysOfferLiveColour, borderRadius: BorderRadius.circular(4)),
                    child: Text("LIVE in Today's Offers until ${_date(end)}", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
              ]),
              trailing: busy == id
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : PopupMenuButton<String>(
                      key: ValueKey('item-photo-menu-$id'),
                      onSelected: (v) => switch (v) { 'camera' => onCamera(id), 'gallery' => onGallery(id), 'search' => onSearchTime?.call(id), _ => onOurs(id) },
                      itemBuilder: (_) => [
                        if (a == null || !a.full || item['ownPhotoStatus'] == 'pending' || item['ownPhoto'] == true) ...[
                          const PopupMenuItem(value: 'camera', child: Text('Take my own photo')),
                          const PopupMenuItem(value: 'gallery', child: Text('Choose my own photo')),
                        ],
                        if (item['ownPhoto'] == true || item['ownPhotoStatus'] == 'pending') const PopupMenuItem(value: 'ours', child: Text('Use your standard photo')),
                        if (onSearchTime != null) const PopupMenuItem(value: 'search', child: Text('How long it shows in search')),
                      ],
                    ),
            ),
        ]),
      ),
    );
  }

  /// How long the item shows in search, and whether that time has passed. Null when the vendor never chose (it shows as before).
  (String, bool)? _search(Map<String, dynamic> item) {
    final until = item['searchUntilMs'];
    if (until is! num) return null;
    final end = DateTime.fromMillisecondsSinceEpoch(until.toInt());
    if (end.isAfter(now ?? DateTime.now())) return ('Shows in search until ${_date(end)}', false);
    return ('Not in search now (its time ended ${_date(end)}). Choose a new time from the menu.', true);
  }

  String _status(Map<String, dynamic> item) {
    if (item['ownPhotoStatus'] == 'pending') return 'Your own photo is waiting for the admin';
    if (item['ownPhotoStatus'] == 'rejected') return 'Your photo was not approved. Send another';
    if (item['customItem'] == true && item['ownPhoto'] != true) return 'Not in the catalog: add your own photo; the item shows after it is checked';
    if (item['awaitingOwnPhoto'] == true) return 'This category needs your own photo: the item shows after it is approved';
    if (item['ownPhoto'] == true) return 'Your own photo';
    return 'Our standard photo';
  }
}
