import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../ui/moderation_dialogs.dart' show ApplicationPhoto;
import '../../ui/photo_check.dart' show PhotoCheck;
import '../home_module.dart';

Widget _build(Store store) => AdminItemPhotosPage(store: store);

/// Admin > Settings > Item photos (listed in module_admin.dart).
const itemPhotosAdminSection = ModuleAdminSection(id: 'itemPhotos', title: 'Item photos', icon: Icons.photo_library_outlined, hint: "Photo rules, own-photo categories and vendors' photos to check", build: _build);

/// Vendors' own item photos waiting for the photo check (with the Google check), oldest first. Approved, the photo becomes the item's
/// photo; rejected, it is deleted and the vendor sees the reason.
class AdminItemPhotosPage extends StatelessWidget {
  const AdminItemPhotosPage({super.key, required this.store});
  final Store store;

  Future<void> _decide(BuildContext context, String productId, bool approved) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.call('reviewItemPhoto', {'productId': productId, 'approved': approved, if (!approved) 'reason': 'Not a clear, own photo of this item'});
      messenger.showSnackBar(SnackBar(content: Text(approved ? 'Approved: it is the item photo now' : 'Not approved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addToCatalog(BuildContext context, String productId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.call('addPhotoToCatalog', {'productId': productId});
      messenger.showSnackBar(const SnackBar(content: Text('Added to the catalog: every vendor can pick this photo now')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorItemPhotos').where('status', isEqualTo: 'pending').snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Item photos could not load.'));
      final docs = [...snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]]
        ..sort((a, b) => ((a.data()['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((b.data()['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
      return ListView(padding: const EdgeInsets.all(20), children: [
        Text('Photo rules', style: Theme.of(context).textTheme.headlineSmall),
        const Text(
          'Every vendor has 1 shop photo that is not counted. Extra photos: free vendors get the number in Plans > Free plan > Photos; '
          'paid vendors get their plan\'s "Extra photos" (Plans > Edit plan). When a paid plan ends, the first extra photos stay and the rest are deleted.',
          key: ValueKey('photo-rules-text'),
        ),
        const SizedBox(height: 12),
        OwnPhotoCategories(store: store),
        const Divider(height: 32),
        Text('Item photos to check', style: Theme.of(context).textTheme.headlineSmall),
        Text(snapshot.hasData ? '${docs.length} waiting, oldest first.' : 'Loading...'),
        for (final d in docs)
          Card(
            key: ValueKey('admin-item-photo-${d.id}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d.data()['name'] ?? d.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ApplicationPhoto(path: '${d.data()['path']}', height: 160, width: 200),
                PhotoCheck(store: store, path: '${d.data()['path']}'),
                OverflowBar(spacing: 8, children: [
                  FilledButton(key: ValueKey('admin-item-photo-approve-${d.id}'), onPressed: () => _decide(context, d.id, true), child: const Text('Approve')),
                  OutlinedButton(key: ValueKey('admin-item-photo-reject-${d.id}'), onPressed: () => _decide(context, d.id, false), child: const Text('Reject')),
                ]),
              ]),
            ),
          ),
        const Divider(height: 32),
        Text('Add to catalog', style: Theme.of(context).textTheme.headlineSmall),
        const Text("A vendor's own photo that is in use can become the standard photo of that item in the Product Image Library, for every vendor. Vendors then pick it instead of uploading again."),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: store.firestore.collection('vendorItemPhotos').where('status', isEqualTo: 'approved').limit(50).snapshots(),
          builder: (context, approved) => Column(children: [
            if (approved.hasData && approved.data!.docs.isEmpty) const ListTile(title: Text('No own photos in use yet.')),
            for (final d in approved.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              ListTile(
                key: ValueKey('admin-item-photo-approved-${d.id}'),
                title: Text('${d.data()['name'] ?? d.id}'),
                subtitle: Text(d.data()['autoApproved'] == true ? 'Checked by AI' : 'Checked by the office'),
                trailing: OutlinedButton(key: ValueKey('admin-item-photo-catalog-${d.id}'), onPressed: () => _addToCatalog(context, d.id), child: const Text('Add to catalog')),
              ),
          ]),
        ),
      ]);
    },
  );
}

/// The categories whose items need the vendor's own photo (for example sarees): a switch for each. Items of a ticked category stay hidden
/// until the vendor's own photo is approved. The same switch is in Catalog > Categories > edit.
class OwnPhotoCategories extends StatelessWidget {
  const OwnPhotoCategories({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('categories').snapshots(),
    builder: (context, snapshot) => OwnPhotoCategoriesView(
      categories: [
        for (final d in snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
          if (d.data()['active'] != false) (d.id, '${d.data()['name'] ?? d.id}', d.data()['ownPhotoRequired'] == true),
      ]..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase())),
      onChanged: (id, on) => store.firestore.collection('categories').doc(id).update({'ownPhotoRequired': on}),
    ),
  );
}

class OwnPhotoCategoriesView extends StatelessWidget {
  const OwnPhotoCategoriesView({super.key, required this.categories, required this.onChanged});
  final List<(String, String, bool)> categories;
  final Future<void> Function(String id, bool on) onChanged;

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('own-photo-categories'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Categories that need the vendor\'s own photo', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('Tick a category (for example Sarees) and its new items stay hidden until the vendor\'s own photo is approved. Other categories may use our standard photo.'),
        if (categories.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No categories yet.')),
        for (final (id, name, on) in categories)
          SwitchListTile(
            key: ValueKey('own-photo-category-$id'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(name),
            subtitle: Text(on ? 'Own photo required' : 'Standard photo allowed'),
            value: on,
            onChanged: (v) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await onChanged(id, v);
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            },
          ),
      ]),
    ),
  );
}
