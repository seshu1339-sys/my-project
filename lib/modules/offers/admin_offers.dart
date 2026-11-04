import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'offer_model.dart';
import 'offers_page.dart' show offerPhoto;

Widget _build(Store store) => AdminOffersPage(store: store);

/// The Vendor Offers tab of the admin panel (listed in module_admin.dart).
const offersAdminSection = ModuleAdminSection(id: 'offers', title: 'Vendor Offers', icon: Icons.local_offer_outlined, hint: 'Offers made by vendors', build: _build);

/// Admin > Vendor Offers: reads the offers and the approval switch, and saves through the module's own callables.
class AdminOffersPage extends StatelessWidget {
  const AdminOffersPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: store.firestore.collection('vendorOffers').orderBy('updatedAt', descending: true).limit(300).snapshots(),
    builder: (context, offers) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('vendorOffersConfig').doc('main').snapshots(),
      builder: (context, config) {
        if (offers.hasError) return const Center(child: Text('Offers could not load.'));
        if (!offers.hasData) return const Center(child: CircularProgressIndicator());
        return AdminOffersView(
          offers: [for (final doc in offers.data!.docs) VendorOffer.fromData(doc.id, doc.data())],
          approvalRequired: config.data?.data()?['approvalRequired'] == true,
          onApproval: (on) => store.call('saveVendorOffersConfig', {'approvalRequired': on}),
          onApprove: (id) => store.call('reviewVendorOffer', {'offerId': id, 'action': 'approve'}),
          onRemove: (id, reason) => store.call('reviewVendorOffer', {'offerId': id, 'action': 'remove', 'reason': reason}),
        );
      },
    ),
  );
}

class AdminOffersView extends StatelessWidget {
  const AdminOffersView({super.key, required this.offers, required this.approvalRequired, required this.onApproval, required this.onApprove, required this.onRemove, this.now});
  final List<VendorOffer> offers;
  final bool approvalRequired;
  final Future<void> Function(bool on) onApproval;
  final Future<void> Function(String offerId) onApprove;
  final Future<void> Function(String offerId, String reason) onRemove;
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

  Future<void> _remove(BuildContext context, VendorOffer offer) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _RemoveDialog(offer: offer));
    if (reason != null && context.mounted) await _run(context, () => onRemove(offer.id, reason), 'Offer removed');
  }

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final waiting = offers.where((o) => o.waiting && !o.endedAt(today)).toList();
    final others = offers.where((o) => !waiting.contains(o)).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Vendor Offers', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Offers vendors made themselves, with their own photos and prices. They have nothing to do with plans or payments.'),
      SwitchListTile(
        key: const ValueKey('offers-approval'),
        contentPadding: EdgeInsets.zero,
        title: const Text('New offers need approval'),
        subtitle: const Text('Off: an offer goes live at once, and you can remove it any time. On: new and edited offers wait for you.'),
        value: approvalRequired,
        onChanged: (on) => _run(context, () => onApproval(on), 'Saved'),
      ),
      if (offers.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No offers yet.', key: ValueKey('admin-offers-empty')))),
      for (final offer in [...waiting, ...others])
        Card(
          child: ListTile(
            key: ValueKey('admin-offer-${offer.id}'),
            leading: offer.photos.isEmpty ? null : ClipRRect(borderRadius: BorderRadius.circular(6), child: offerPhoto(offer.photos.first, width: 56, height: 56)),
            title: Text(offer.title),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${offerPriceText(offer.offerPrice)} • ${offer.shopName} • ${offerStatusText(offer, today)}'),
              Wrap(spacing: 4, children: [
                if (offer.waiting) TextButton(key: ValueKey('admin-offer-approve-${offer.id}'), onPressed: () => _run(context, () => onApprove(offer.id), 'Offer approved'), child: const Text('Approve')),
                if (!offer.removed) TextButton(key: ValueKey('admin-offer-remove-${offer.id}'), onPressed: () => _remove(context, offer), child: const Text('Remove')),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

class _RemoveDialog extends StatefulWidget {
  const _RemoveDialog({required this.offer});
  final VendorOffer offer;

  @override
  State<_RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends State<_RemoveDialog> {
  final formKey = GlobalKey<FormState>();
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Remove "${widget.offer.title}"?'),
    content: Form(
      key: formKey,
      child: TextFormField(
        key: const ValueKey('offer-remove-reason'),
        controller: reason,
        maxLength: 200,
        decoration: const InputDecoration(labelText: 'Reason (the vendor sees this)'),
        validator: (v) => (v ?? '').trim().length < 2 ? 'Give a short reason' : null,
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: const ValueKey('offer-remove-yes'),
        onPressed: () {
          if (formKey.currentState!.validate()) Navigator.pop(context, reason.text.trim());
        },
        child: const Text('Remove'),
      ),
    ],
  );
}
