import 'dart:math' as math;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/store.dart';
import '../../services/location.dart';
import '../../domain/catalog.dart';
import '../../services/server_clock.dart';
import 'staff_area_model.dart';

/// A live photo taken at the shop: where (real GPS, never a mock location), how exact, and when. The server checks it again.
class LivePhoto {
  const LivePhoto({required this.id, required this.latitude, required this.longitude, required this.accuracy, required this.mocked, required this.takenAt});
  final String id;
  final double latitude, longitude, accuracy;
  final bool mocked;
  final DateTime takenAt;
  Map<String, dynamic> toData() => {'id': id, 'latitude': latitude, 'longitude': longitude, 'accuracy': accuracy, 'mocked': mocked, 'takenAt': takenAt.millisecondsSinceEpoch};
}

/// Metres between two places.
double metresBetween(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * math.pi / 180;
  final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lon2 - lon1) / 2), 2);
  return 6371000 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Why this live photo cannot be used at [shop], or null (the same checks as the server's, so the staff member knows at once).
String? livePhotoProblem(LivePhoto photo, AreaShop shop) {
  if (photo.mocked) return 'Fake GPS (a mock location app) is not allowed. Turn it off and take the photo again at the shop.';
  if (photo.accuracy > 100) return 'Your GPS is not exact enough. Wait for a better signal at the shop and try again.';
  final m = metresBetween(photo.latitude, photo.longitude, shop.latitude, shop.longitude);
  if (m > livePhotoMaxMetres) return 'You are ${m.round()} m from ${shop.name}. Go to the shop (within $livePhotoMaxMetres m) and take the photo there.';
  return null;
}

/// Staff app: add a Today's Offer for a shop in my area. Choose the shop, choose the item from the admin's list (its photo comes with
/// it), enter the normal price and a lower offer price, and the date (today unless changed). It ends by itself after that day. Staff
/// never enter a vendor's normal item rates and never change a vendor's profile, photos or items.
class StaffOfferForm extends StatefulWidget {
  const StaffOfferForm({super.key, required this.store, required this.shops, this.items, this.onSave, this.now, this.capture});
  final Store store;
  final List<AreaShop> shops;
  // Test seam: taking the live photo (camera only + GPS + upload). The real one never offers the gallery.
  final Future<LivePhoto?> Function()? capture;
  // Test seams: the admin's item list, what saving does, and the clock.
  final Future<List<Entry>> Function()? items;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? onSave;
  final DateTime Function()? now;

  @override
  State<StaffOfferForm> createState() => _StaffOfferFormState();
}

class _StaffOfferFormState extends State<StaffOfferForm> {
  final formKey = GlobalKey<FormState>();
  final search = TextEditingController();
  final regular = TextEditingController();
  final offer = TextEditingController();
  String? shopId;
  Entry? item;
  late final today = istDayOf((widget.now ?? ServerClock.now)());
  late final Future<List<Entry>> library = (widget.items ?? _library)();
  bool busy = false;
  String? error;
  LivePhoto? photo;

  /// Camera only (no gallery), the GPS at that moment (a mock location is refused), and the upload to the staff member's staffOfferPhotos folder.
  Future<LivePhoto?> _capture() async {
    final uid = widget.store.user?.uid;
    if (uid == null) throw StateError('Sign in first.');
    final file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80, preferredCameraDevice: CameraDevice.rear);
    if (file == null) return null;
    final position = await currentPosition(action: 'check that you are at the shop');
    final takenAt = DateTime.now();
    final id = '${takenAt.millisecondsSinceEpoch}${uid.substring(0, math.min(6, uid.length))}';
    await FirebaseStorage.instance.ref('staffOfferPhotos/$uid/$id').putData(await file.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
    return LivePhoto(id: id, latitude: position.latitude, longitude: position.longitude, accuracy: position.accuracy, mocked: position.isMocked, takenAt: takenAt);
  }

  Future<void> _takePhoto() async {
    final shop = widget.shops.where((s) => s.id == shopId).firstOrNull;
    if (shop == null) return setState(() => error = 'Choose the shop first, then take the photo standing there.');
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final taken = await (widget.capture ?? _capture)();
      if (taken != null) {
        final problem = livePhotoProblem(taken, shop);
        setState(() {
          photo = problem == null ? taken : null;
          error = problem;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<List<Entry>> _library() async {
    final docs = await widget.store.firestore.collection('productImageLibrary').limit(3000).get();
    return [for (final d in docs.docs) if (d.data()['active'] != false) Entry(d.id, d.data())]..sort((a, b) => a.text('name').compareTo(b.text('name')));
  }

  @override
  void dispose() {
    search.dispose();
    regular.dispose();
    offer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => error = null);
    if (!formKey.currentState!.validate()) return;
    if (shopId == null) return setState(() => error = 'Choose the shop.');
    if (item == null) return setState(() => error = 'Choose the item from the list.');
    if (photo == null) return setState(() => error = 'Take a live photo at the shop first.');
    setState(() => busy = true);
    try {
      final data = {
        'shopId': shopId,
        'libraryItemId': item!.id,
        'regularPrice': num.parse(regular.text.trim()),
        'offerPrice': num.parse(offer.text.trim()),
        'photo': photo!.toData(),
      };
      await (widget.onSave ?? (data) => widget.store.call('addStaffTodayOffer', data))(data);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Update a rate')),
    body: Form(
      key: formKey,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('staff-offer-shop'),
          initialValue: shopId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Shop in your area'),
          items: [for (final s in widget.shops) DropdownMenuItem(value: s.id, child: Text(s.offerToday ? '${s.name} (has an offer today)' : s.name, overflow: TextOverflow.ellipsis))],
          // A new shop needs a new live photo there.
          onChanged: (v) => setState(() {
            shopId = v;
            photo = null;
          }),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('staff-offer-photo'),
          onPressed: busy ? null : _takePhoto,
          icon: Icon(photo == null ? Icons.photo_camera_outlined : Icons.check_circle, color: photo == null ? null : Colors.green),
          label: Text(photo == null ? 'Take a live photo at the shop' : 'Live photo taken at the shop'),
        ),
        const Text('Camera only, with GPS on, standing at the shop (within 100 m). Fake GPS apps are blocked; photos from anywhere else never count.', style: TextStyle(fontSize: 12)),
        if (widget.shops.isEmpty) const Padding(padding: EdgeInsets.only(top: 4), child: Text('No shop with a map place is inside your area yet.')),
        const SizedBox(height: 12),
        FutureBuilder<List<Entry>>(
          future: library,
          builder: (context, snapshot) {
            final q = search.text.trim().toLowerCase();
            final all = snapshot.data ?? const <Entry>[];
            final shown = [for (final e in all) if (q.isEmpty || e.text('name').toLowerCase().contains(q)) e].take(30).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (item != null)
                ListTile(
                  key: const ValueKey('staff-offer-item-chosen'),
                  contentPadding: EdgeInsets.zero,
                  leading: _photo(item!),
                  title: Text(item!.text('name'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('The photo comes from the item list'),
                  trailing: TextButton(onPressed: () => setState(() => item = null), child: const Text('Change')),
                )
              else ...[
                TextField(
                  key: const ValueKey('staff-offer-item-search'),
                  controller: search,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Item (from the list)'),
                  onChanged: (_) => setState(() {}),
                ),
                if (!snapshot.hasData) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
                for (final e in shown)
                  ListTile(key: ValueKey('staff-offer-item-${e.id}'), dense: true, leading: _photo(e), title: Text(e.text('name')), onTap: () => setState(() => item = e)),
              ],
            ]);
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('staff-offer-regular'),
          controller: regular,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Normal price (₹)'),
          validator: (v) => (num.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter the normal price' : null,
        ),
        TextFormField(
          key: const ValueKey('staff-offer-price'),
          controller: offer,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Offer price (₹)'),
          validator: (v) {
            final o = num.tryParse((v ?? '').trim()) ?? 0;
            final r = num.tryParse(regular.text.trim()) ?? 0;
            if (o <= 0) return 'Enter the offer price';
            return r > 0 && o >= r ? 'Must be lower than the normal price' : null;
          },
        ),
        const SizedBox(height: 12),
        const Text("This is today's rate. It ends by itself at midnight. How long a vendor's own offers show is the vendor's choice.", key: ValueKey('staff-offer-today'), style: TextStyle(fontSize: 12)),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, key: const ValueKey('staff-offer-error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(key: const ValueKey('staff-offer-save'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving...' : 'Save offer')),
      ]),
    ),
  );

  Widget _photo(Entry e) {
    final url = e.text('imageUrl');
    return SizedBox(
      width: 44,
      height: 44,
      child: url.isEmpty ? const Icon(Icons.image_outlined) : ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_outlined))),
    );
  }
}
