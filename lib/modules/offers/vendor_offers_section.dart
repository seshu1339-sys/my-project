import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/post_duration.dart' show showPostDayChoices, postDurationNotice;
import '../../data/store.dart';
import 'offer_model.dart';
import 'offers_page.dart' show offerPhoto;

const maxOfferPhotos = 3;
const offerDays = [3, 7, 15, 30];

/// A new photo chosen in the editor, kept on the phone until Save.
class NewOfferPhoto {
  const NewOfferPhoto(this.file, this.bytes);
  final XFile? file;
  final Uint8List bytes;
}

/// What the editor returns: the fields to save, and the new photos still to upload.
class OfferDraft {
  const OfferDraft(this.fields, this.keptPhotos, this.newPhotos);
  final Map<String, dynamic> fields;
  final List<String> keptPhotos;
  final List<NewOfferPhoto> newPhotos;
}

/// The My Offers card of the vendor app. It only needs the store and the vendor id.
class VendorOffersSection extends StatefulWidget {
  const VendorOffersSection({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;

  @override
  State<VendorOffersSection> createState() => _VendorOffersSectionState();
}

class _VendorOffersSectionState extends State<VendorOffersSection> {
  Store get store => widget.store;
  late final stream = store.firestore.collection('vendorOffers').where('vendorId', isEqualTo: widget.uid).snapshots();

  Future<void> _save(OfferDraft draft) async {
    final uploaded = <String>[];
    for (final photo in draft.newPhotos) {
      uploaded.add(await store.upload(photo.file!, folder: 'vendorOffers/${widget.uid}'));
    }
    await store.call('saveVendorOffer', {...draft.fields, 'photos': [...draft.keptPhotos, ...uploaded]});
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    // A running paid plan (Silver, Gold or Premium) unlocks the nearby alert.
    stream: store.firestore.collection('vendorPremium').doc(widget.uid).snapshots(),
    builder: (context, premium) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) => VendorOffersView(
        offers: [for (final doc in snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) VendorOffer.fromData(doc.id, doc.data())],
        onSave: _save,
        onDelete: (id) => store.call('deleteVendorOffer', {'offerId': id}),
        canAlert: premium.data?.data()?['active'] == true,
        planKm: (premium.data?.data()?['radiusKm'] as num?)?.toDouble(),
        durationNote: postDurationNotice(store.business),
      ),
    ),
  );
}

/// The card itself: the Add button and the vendor's own offers.
class VendorOffersView extends StatefulWidget {
  const VendorOffersView({super.key, required this.offers, required this.onSave, required this.onDelete, this.now, this.canAlert = false, this.planKm, this.durationNote});
  // The admin's post duration, said before posting (lib/domain/post_duration.dart).
  final String? durationNote;
  // Paid vendors only: the nearby alert choice in the editor. It reaches the plan's km.
  final bool canAlert;
  final double? planKm;
  final List<VendorOffer> offers;
  final Future<void> Function(OfferDraft draft) onSave;
  final Future<void> Function(String offerId) onDelete;
  final DateTime? now;

  @override
  State<VendorOffersView> createState() => _VendorOffersViewState();
}

class _VendorOffersViewState extends State<VendorOffersView> {
  bool busy = false;
  DateTime get now => widget.now ?? DateTime.now();

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _edit([VendorOffer? offer]) async {
    final draft = await showDialog<OfferDraft>(context: context, builder: (_) => OfferEditorDialog(offer: offer, now: now, canAlert: widget.canAlert, planKm: widget.planKm, durationNote: widget.durationNote));
    if (draft != null && mounted) await _run(() => widget.onSave(draft), 'Offer saved');
  }

  Future<void> _delete(VendorOffer offer) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this offer?'),
        content: Text(offer.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Keep')),
          FilledButton(key: const ValueKey('offer-delete-yes'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true && mounted) await _run(() => widget.onDelete(offer.id), 'Offer deleted');
  }

  @override
  Widget build(BuildContext context) {
    final offers = [...widget.offers]..sort((a, b) => (a.endedAt(now) ? 1 : 0).compareTo(b.endedAt(now) ? 1 : 0));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My Offers', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(widget.durationNote ?? 'Show customers an offer with your own photos and prices. Offers are free and separate from plans.'),
          const SizedBox(height: 8),
          FilledButton.icon(key: const ValueKey('offer-add'), onPressed: busy ? null : _edit, icon: const Icon(Icons.add), label: const Text('Add offer')),
          for (final offer in offers)
            ListTile(
              key: ValueKey('my-offer-${offer.id}'),
              contentPadding: EdgeInsets.zero,
              leading: offer.photos.isEmpty ? null : ClipRRect(borderRadius: BorderRadius.circular(6), child: offerPhoto(offer.photos.first, width: 56, height: 56)),
              title: Text(offer.title),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${offerPriceText(offer.offerPrice)} • ${offerStatusText(offer, now)}'),
                if (offerAlertText(offer) case final alert?) Text(alert, key: ValueKey('offer-alert-status-${offer.id}'), style: const TextStyle(fontSize: 12)),
                Wrap(spacing: 4, children: [
                  if (!offer.removed) TextButton(key: ValueKey('offer-edit-${offer.id}'), onPressed: busy ? null : () => _edit(offer), child: Text(offer.endedAt(now) ? 'Run again' : 'Edit')),
                  TextButton(key: ValueKey('offer-delete-${offer.id}'), onPressed: busy ? null : () => _delete(offer), child: const Text('Delete')),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Name, prices, days and photos of an offer. Pops an [OfferDraft], or null when cancelled.
class OfferEditorDialog extends StatefulWidget {
  const OfferEditorDialog({super.key, this.offer, required this.now, this.pickPhoto, this.canAlert = true, this.planKm, this.durationNote});
  // The admin's post duration, said before posting (lib/domain/post_duration.dart).
  final String? durationNote;
  // Paid vendors (a running plan) may alert customers nearby; free vendors see no alert choice. The alert reaches the plan's km.
  final bool canAlert;
  final double? planKm;
  final VendorOffer? offer;
  final DateTime now;

  /// Chooses a photo; the phone's gallery unless a test gives another.
  final Future<NewOfferPhoto?> Function()? pickPhoto;

  @override
  State<OfferEditorDialog> createState() => _OfferEditorDialogState();
}

String _km(double km) => km == km.roundToDouble() ? '${km.toInt()}' : '$km';

class _OfferEditorDialogState extends State<OfferEditorDialog> {
  final formKey = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.offer?.title ?? '');
  late final details = TextEditingController(text: widget.offer?.details ?? '');
  late final offerPrice = TextEditingController(text: widget.offer == null ? '' : '${widget.offer!.offerPrice}');
  late final regularPrice = TextEditingController(text: widget.offer?.regularPrice == null ? '' : '${widget.offer!.regularPrice}');
  late final running = widget.offer != null && !widget.offer!.endedAt(widget.now);
  // null keeps the end date of an offer that is still running.
  // With the day choices hidden the longest choice is sent (null keeps a running offer's end): the admin's post duration ends it first.
  late int? days = running ? null : (showPostDayChoices ? 7 : offerDays.last);
  // The nearby alert (on or off; it reaches the plan km): chosen for a new offer or one that runs again; a running offer's edit keeps
  // its own.
  bool alertOn = false;
  late final kept = [...?widget.offer?.photos];
  final added = <NewOfferPhoto>[];
  String? photoError;

  int get photoCount => kept.length + added.length;

  @override
  void dispose() {
    title.dispose();
    details.dispose();
    offerPrice.dispose();
    regularPrice.dispose();
    super.dispose();
  }

  Future<NewOfferPhoto?> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    return file == null ? null : NewOfferPhoto(file, await file.readAsBytes());
  }

  Future<void> _addPhoto({bool camera = false}) async {
    try {
      final photo = await (widget.pickPhoto ?? () => _pick(camera ? ImageSource.camera : ImageSource.gallery))();
      if (photo != null && mounted) {
        setState(() {
          added.add(photo);
          photoError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => photoError = '$e');
    }
  }

  void _save() {
    final ok = formKey.currentState!.validate();
    if (photoCount == 0) setState(() => photoError = 'Add at least one photo of your own');
    if (!ok || photoCount == 0) return;
    final regular = regularPrice.text.trim();
    Navigator.pop(
      context,
      OfferDraft({
        if (widget.offer != null) 'offerId': widget.offer!.id,
        'title': title.text.trim(),
        'details': details.text.trim(),
        'offerPrice': num.parse(offerPrice.text.trim()),
        if (regular.isNotEmpty) 'regularPrice': num.parse(regular),
        if (days != null) 'days': days,
        if (!running && widget.canAlert) 'alert': alertOn,
      }, kept, added),
    );
  }

  Widget _thumb(Widget image, VoidCallback onRemove) => Stack(children: [
    ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 72, height: 72, child: image)),
    Positioned(
      right: 0,
      top: 0,
      child: InkWell(onTap: onRemove, child: const CircleAvatar(radius: 11, child: Icon(Icons.close, size: 14))),
    ),
  ]);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.offer == null ? 'Add offer' : 'Edit offer'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(
              key: const ValueKey('offer-title'),
              controller: title,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Offer name'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter an offer name' : null,
            ),
            TextFormField(key: const ValueKey('offer-details'), controller: details, maxLength: 300, maxLines: 2, decoration: const InputDecoration(labelText: 'Details (optional)')),
            TextFormField(
              key: const ValueKey('offer-price'),
              controller: offerPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Offer price (₹)'),
              validator: (v) => (num.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter a price above 0' : null,
            ),
            TextFormField(
              key: const ValueKey('offer-regular-price'),
              controller: regularPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Regular price (₹, optional)'),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return null;
                final regular = num.tryParse(text);
                final offer = num.tryParse(offerPrice.text.trim());
                return regular == null || offer == null || regular <= offer ? 'Must be above the offer price' : null;
              },
            ),
            const SizedBox(height: 8),
            if (widget.durationNote != null) Text(widget.durationNote!, key: const ValueKey('offer-duration-note')),
            if (showPostDayChoices) DropdownButton<int?>(
              key: const ValueKey('offer-days'),
              isExpanded: true,
              value: days,
              items: [
                if (running) DropdownMenuItem<int?>(value: null, child: Text('Keep end date (${offerDate(widget.offer!.endsAt!)})')),
                for (final count in offerDays) DropdownMenuItem<int?>(value: count, child: Text('Run for $count days')),
              ],
              onChanged: (v) => setState(() => days = v),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final url in kept) _thumb(offerPhoto(url), () => setState(() => kept.remove(url))),
              for (final photo in added) _thumb(Image.memory(photo.bytes, fit: BoxFit.cover), () => setState(() => added.remove(photo))),
              if (photoCount < maxOfferPhotos) ...[
                OutlinedButton.icon(key: const ValueKey('offer-take-photo'), onPressed: () => _addPhoto(camera: true), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo')),
                OutlinedButton.icon(key: const ValueKey('offer-add-photo'), onPressed: _addPhoto, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add photo')),
              ],
            ]),
            if (photoError != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(photoError!, key: const ValueKey('offer-photo-error'), style: const TextStyle(color: Colors.red))),
            if (!running && widget.canAlert) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                key: const ValueKey('offer-alert'),
                contentPadding: EdgeInsets.zero,
                value: alertOn,
                onChanged: (v) => setState(() => alertOn = v),
                title: const Text('Alert customers nearby', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Customers with notifications on get one alert, up to ${widget.planKm == null ? 'your plan km' : '${_km(widget.planKm!)} km (your plan)'} from your shop. One alert a day.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ] else if (offerAlertText(widget.offer!) case final alert?)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(alert, style: const TextStyle(fontSize: 12))),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('offer-save'), onPressed: _save, child: const Text('Save')),
    ],
  );
}
