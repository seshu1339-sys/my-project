import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'admin_premium_data.dart';
import 'wholesale_form.dart';

Widget _build(Store store) => AdminPremiumPage(store: store);

/// The Premium tab of the admin panel (listed in module_admin.dart).
const premiumAdminSection = ModuleAdminSection(id: 'premium', title: 'Premium', icon: Icons.star_outline, hint: 'Wholesale offers and vendors\' Today\'s Offers', build: _build);

/// Admin > Premium: reads the offers and saves through the callables of the wholesale and Today's Offer server modules.
class AdminPremiumPage extends StatelessWidget {
  const AdminPremiumPage({super.key, required this.store});
  final Store store;

  Future<void> _save(WholesaleDraft draft) async {
    final photoUrl = draft.photo == null ? draft.fields['photoUrl'] : await store.upload(draft.photo!, folder: 'wholesaleOffers');
    await store.call('saveWholesaleOffer', {...draft.fields, 'photoUrl': photoUrl});
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('wholesaleOffers').orderBy('validUntil').snapshots(),
    builder: (context, wholesale) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('vendorTodaysOffers').where('endsAt', isGreaterThan: Timestamp.now()).orderBy('endsAt').snapshots(),
      builder: (context, offers) {
        if (wholesale.hasError || offers.hasError) return const Center(child: Text('Premium offers could not load.'));
        if (!wholesale.hasData || !offers.hasData) return const Center(child: CircularProgressIndicator());
        return AdminPremiumView(
          wholesale: [for (final doc in wholesale.data!.docs) AdminWholesale.fromData(doc.id, doc.data())],
          vendorOffers: [for (final doc in offers.data!.docs) AdminVendorOffer.fromData(doc.id, doc.data())],
          shopName: (id) => store.entries('shops').where((s) => s.id == id).firstOrNull?.text('name') ?? id,
          onSave: _save,
          onDelete: (id) => store.call('deleteWholesaleOffer', {'offerId': id}),
          onRemoveOffer: (offerId) => store.call('removeTodaysOffer', {'offerId': offerId}),
        );
      },
    ),
  );
}

class AdminPremiumView extends StatelessWidget {
  const AdminPremiumView({super.key, required this.wholesale, required this.vendorOffers, required this.shopName, required this.onSave, required this.onDelete, required this.onRemoveOffer, this.now});
  final List<AdminWholesale> wholesale;
  final List<AdminVendorOffer> vendorOffers;
  final String Function(String shopId) shopName;
  final Future<void> Function(WholesaleDraft draft) onSave;
  final Future<void> Function(String offerId) onDelete;
  final Future<void> Function(String vendorId) onRemoveOffer;
  final DateTime? now;

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _edit(BuildContext context, [AdminWholesale? offer]) async {
    final draft = await showDialog<WholesaleDraft>(context: context, builder: (_) => WholesaleFormDialog(offer: offer, now: now ?? DateTime.now()));
    if (draft != null && context.mounted) await _run(context, () => onSave(draft), 'Saved');
  }

  Future<bool> _sure(BuildContext context, String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(key: const ValueKey('premium-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Yes')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
        Text('Wholesale offers', style: Theme.of(context).textTheme.headlineSmall),
        FilledButton.icon(key: const ValueKey('wholesale-add'), onPressed: () => _edit(context), icon: const Icon(Icons.add), label: const Text('Add offer')),
      ]),
      const Text('Only vendors with a running plan see these. A tap on a card calls the wholesaler. An offer hides by itself after its validity date.'),
      const SizedBox(height: 8),
      if (wholesale.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No wholesale offers yet.', key: ValueKey('admin-wholesale-empty')))),
      for (final offer in wholesale)
        Card(
          child: ListTile(
            key: ValueKey('admin-wholesale-${offer.id}'),
            title: Text(offer.name),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${premiumPrice(offer.price)} • Minimum ${offer.minQuantity} • ${offer.wholesaler} • ${offer.phone}'),
              Text(offer.validUntil.isAfter(today) ? 'Valid until ${premiumDate(offer.validUntil)}' : 'Ended on ${premiumDate(offer.validUntil)}'),
              Wrap(spacing: 4, children: [
                TextButton(key: ValueKey('admin-wholesale-edit-${offer.id}'), onPressed: () => _edit(context, offer), child: const Text('Edit')),
                TextButton(
                  key: ValueKey('admin-wholesale-delete-${offer.id}'),
                  onPressed: () async {
                    if (await _sure(context, 'Delete ${offer.name}?') && context.mounted) await _run(context, () => onDelete(offer.id), 'Deleted');
                  },
                  child: const Text('Delete'),
                ),
              ]),
            ]),
          ),
        ),
      const SizedBox(height: 20),
      Text("Vendors' Today's Offers", style: Theme.of(context).textTheme.headlineSmall),
      const Text('These go live without approval. Remove one if it is wrong; the vendor is told and can submit a new one.'),
      const SizedBox(height: 8),
      if (vendorOffers.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No vendor offers are live.', key: ValueKey('admin-vendor-offers-empty')))),
      for (final offer in vendorOffers)
        Card(
          child: ListTile(
            key: ValueKey('admin-vendor-offer-${offer.vendorId}'),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(offer.photoUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56, child: Icon(Icons.image_not_supported_outlined))),
            ),
            title: Text(shopName(offer.shopId)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${premiumPrice(offer.price)} • until ${premiumDate(offer.endsAt)}'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('admin-vendor-offer-remove-${offer.vendorId}'),
                  onPressed: () async {
                    if (await _sure(context, 'Remove this offer?') && context.mounted) await _run(context, () => onRemoveOffer(offer.vendorId), 'Offer removed');
                  },
                  child: const Text('Remove'),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}
