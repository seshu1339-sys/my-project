import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/location.dart';
import 'shop_map.dart';

/// Returns every reason a field entry must not be submitted yet. Mirrors the
/// server-side checks in functions/domain.js (fieldShopDetails/
/// fieldItemDetails) and functions/field-assistant.js's GPS requirement, the
/// same way vendorApplicationErrors() mirrors vendorApplication() — so
/// nothing incomplete is ever sent.
List<String> fieldEntryErrors({
  required bool useExistingShop,
  required bool hasExistingShop,
  required String shopName,
  required String shopAddress,
  required String shopPincode,
  required String itemName,
  required String itemPrice,
  required String itemStock,
  required bool hasPhoto,
  required bool hasLocation,
}) {
  bool between(String v, int min, int max) => v.trim().length >= min && v.trim().length <= max;
  final price = double.tryParse(itemPrice.trim());
  final stock = int.tryParse(itemStock.trim());
  return [
    if (useExistingShop && !hasExistingShop) 'Choose a shop.',
    if (!useExistingShop && !between(shopName, 2, 120)) 'Enter the shop name.',
    if (!useExistingShop && !between(shopAddress, 5, 500)) 'Enter the shop address.',
    if (!useExistingShop && !RegExp(r'^\d{6}$').hasMatch(shopPincode.trim())) 'Enter a valid six-digit pincode.',
    if (!between(itemName, 2, 120)) 'Enter the item name.',
    if (price == null || price < 0) 'Enter a valid price.',
    if (stock == null || stock < 0) 'Enter the stock quantity as a whole number.',
    if (!hasPhoto) 'Take or choose a photo of the item.',
    if (!hasLocation) "Capture the shop's GPS location.",
  ];
}

/// Capture: existing shop (searchable dropdown) or a brand-new one (name/
/// address/pincode), GPS (always captured fresh, proves the staff member was
/// actually there — required for an existing shop too), item name/price/
/// stock, and one photo. Cannot submit until every required field and the
/// photo are present; GPS auto-captures on open with a "Recapture" fallback,
/// exactly like VendorRegistrationForm.
class FieldEntryForm extends StatefulWidget {
  const FieldEntryForm({super.key, required this.store});
  final Store store;
  @override
  State<FieldEntryForm> createState() => _FieldEntryFormState();
}

class _FieldEntryFormState extends State<FieldEntryForm> {
  Store get store => widget.store;
  bool useExistingShop = true;
  String? existingShopId;
  final shopName = TextEditingController();
  final shopAddress = TextEditingController();
  final shopPincode = TextEditingController();
  final itemName = TextEditingController();
  final itemPrice = TextEditingController();
  final itemStock = TextEditingController();
  late final String submissionId = '${DateTime.now().microsecondsSinceEpoch}';
  // Admin-configurable (settings/business.fieldPhotoLimit), default 2 — a
  // separate setting from vendor's own photo limit, never affecting it.
  late final int photoLimit = store.business.number('fieldPhotoLimit', 2).round().clamp(1, 9);
  // Slots fill in order (1, 2, 3...) so the resulting photoPaths stay
  // contiguous, matching what submitFieldEntry expects; each filled slot can
  // be replaced but not removed, mirroring vendor's own shop-photo slots.
  final photoBytesBySlot = <int, Uint8List>{};
  int? uploadingSlot;
  List<String> errors = const [];
  bool busy = false;
  Position? position;
  String? locationError;
  bool capturingLocation = true;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  Future<void> _captureLocation() async {
    setState(() {
      capturingLocation = true;
      locationError = null;
    });
    try {
      final result = await currentPosition(action: "capture the shop's location");
      if (mounted) setState(() { position = result; capturingLocation = false; });
    } catch (e) {
      if (mounted) setState(() { locationError = '$e'.replaceFirst('Bad state: ', ''); capturingLocation = false; });
    }
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> pickPhoto(int slot, ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() => uploadingSlot = slot);
      final bytes = await file.readAsBytes();
      await store.uploadFieldPhoto(submissionId, slot, file);
      if (!mounted) return;
      setState(() { photoBytesBySlot[slot] = bytes; errors = const []; });
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploadingSlot = null);
    }
  }

  List<String> _errors() {
    return fieldEntryErrors(
      useExistingShop: useExistingShop,
      hasExistingShop: existingShopId != null,
      shopName: shopName.text,
      shopAddress: shopAddress.text,
      shopPincode: shopPincode.text,
      itemName: itemName.text,
      itemPrice: itemPrice.text,
      itemStock: itemStock.text,
      hasPhoto: photoBytesBySlot.isNotEmpty,
      hasLocation: position != null,
    );
  }

  Future<void> submit() async {
    final problems = _errors();
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      await store.call('submitFieldEntry', {
        'shopId': useExistingShop ? existingShopId : '',
        if (!useExistingShop)
          'shop': {
            'name': shopName.text.trim(),
            'address': shopAddress.text.trim(),
            'pincode': shopPincode.text.trim(),
            'latitude': position!.latitude,
            'longitude': position!.longitude,
          },
        'item': {
          'name': itemName.text.trim(),
          'price': double.parse(itemPrice.text.trim()),
          'stock': int.parse(itemStock.text.trim()),
        },
        'submissionId': submissionId,
        'photoCount': photoBytesBySlot.length,
        'visitLatitude': position!.latitude,
        'visitLongitude': position!.longitude,
      });
      if (mounted) {
        toast('Submitted for admin review');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget get _shopSection {
    final shops = store.entries('shops').where((e) => e.active).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Shop', style: TextStyle(fontWeight: FontWeight.bold)),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Existing shop')),
          ButtonSegment(value: false, label: Text('New shop')),
        ],
        selected: {useExistingShop},
        onSelectionChanged: (selection) => setState(() => useExistingShop = selection.first),
      ),
      const SizedBox(height: 8),
      if (useExistingShop)
        DropdownButtonFormField<String>(
          initialValue: existingShopId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Choose the shop you are visiting'),
          items: [for (final s in shops) DropdownMenuItem(value: s.id, child: Text(s.text('name', s.id)))],
          onChanged: (v) => setState(() => existingShopId = v),
        )
      else ...[
        TextField(controller: shopName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Shop name')),
        TextField(controller: shopAddress, maxLines: 2, decoration: const InputDecoration(labelText: 'Shop address')),
        TextField(controller: shopPincode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Pincode', counterText: '')),
      ],
    ])));
  }

  Widget get _locationCard => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Your current location', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text('Captured automatically and required for every visit — it confirms you were actually at the shop.'),
    const SizedBox(height: 8),
    if (capturingLocation)
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Row(children: [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Capturing your location...'),
      ]))
    else if (position != null) ...[
      ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(
        shops: [Entry('me', {'name': 'Your location', 'latitude': position!.latitude, 'longitude': position!.longitude})],
        height: 160,
      )),
      const SizedBox(height: 8),
      Text('Location captured: ${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'),
    ] else if (locationError != null)
      Text(locationError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: capturingLocation ? null : _captureLocation, icon: const Icon(Icons.my_location), label: Text(position != null ? 'Recapture location' : 'Try again')),
  ])));

  // At least one photo is required; slots fill in order (replacing an
  // already-filled slot is allowed, but a slot can't be skipped) up to the
  // admin-configured photoLimit.
  Widget get _photoSection => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Item photos (up to $photoLimit)', style: const TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Wrap(spacing: 16, runSpacing: 12, children: [
      for (var slot = 1; slot <= photoLimit && slot <= photoBytesBySlot.length + 1; slot++) _photoSlot(slot),
    ]),
  ])));

  Widget _photoSlot(int slot) {
    final bytes = photoBytesBySlot[slot];
    final busyHere = uploadingSlot == slot;
    return SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (bytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, width: 160, height: 120, fit: BoxFit.cover))
      else Container(width: 160, height: 120, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add_a_photo_outlined)),
      const SizedBox(height: 4),
      Text(busyHere ? 'Uploading...' : bytes != null ? 'Photo $slot uploaded' : 'Photo $slot'),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: busy || uploadingSlot != null ? null : () => pickPhoto(slot, ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(bytes == null ? 'Choose' : 'Replace')),
        if (!kIsWeb) OutlinedButton.icon(onPressed: busy || uploadingSlot != null ? null : () => pickPhoto(slot, ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Camera')),
      ]),
    ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New field entry')),
    body: Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _shopSection,
        const SizedBox(height: 12),
        _locationCard,
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Item', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: itemName, decoration: const InputDecoration(labelText: 'Item name')),
          TextField(controller: itemPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
          TextField(controller: itemStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')),
        ]))),
        const SizedBox(height: 12),
        _photoSection,
        if (errors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Please fix the following before submitting:', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final e in errors) Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        const SizedBox(height: 16),
        FilledButton(onPressed: busy || uploadingSlot != null ? null : submit, child: Text(busy ? 'Submitting...' : 'Submit for approval')),
      ]),
    )))),
  );

  @override
  void dispose() {
    for (final c in [shopName, shopAddress, shopPincode, itemName, itemPrice, itemStock]) {
      c.dispose();
    }
    super.dispose();
  }
}
