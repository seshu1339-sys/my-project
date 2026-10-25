import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/places.dart';
import '../domain/vendor_items.dart';
import '../services/geocoding.dart';
import '../services/gps_address.dart';
import '../services/location.dart';
import 'library_item_tile.dart';
import 'shop_map.dart';

/// The vendor's photos: photo 1 of the vendor or the shop, and two extra ones (all three are needed).
const staffVendorPhotoNames = ['vendor_1', 'vendor_2', 'vendor_3'];

/// An item's photos: at least 2, at most 3.
const staffItemMinPhotos = 2, staffItemMaxPhotos = 3;

/// One item being added for the vendor: from the admin's library, sold by 1-10 kg or pieces at a price for that quantity, with 2-3 photos.
class StaffItemDraft {
  Entry? libraryItem;
  String? categoryId;
  String unitType = 'kg';
  int quantity = 1;
  final price = TextEditingController();
  // How many of its photos are uploaded (they fill in order: item<i>_1, _2, _3).
  final photos = <Uint8List>[];
}

/// Every reason the vendor cannot be added yet. Mirrors staffVendorDetails() in functions/staff-additions.js.
List<String> staffVendorErrors({
  required String name,
  required String phone,
  required String address,
  required String pincode,
  required bool hasLocation,
  required int vendorPhotos,
  required List<StaffItemDraft> items,
}) {
  bool between(String v, int min, int max) => v.trim().length >= min && v.trim().length <= max;
  return [
    if (!hasLocation) 'Turn on your location (GPS) and capture it: the vendor is added at your location.',
    if (!between(name, 2, 120)) "Enter the vendor's name.",
    if (!RegExp(r'^\+?[0-9][0-9 -]{6,17}$').hasMatch(phone.trim())) "Enter the vendor's phone number.",
    if (!between(address, 5, 500)) 'Enter the address.',
    if (!RegExp(r'^\d{6}$').hasMatch(pincode.trim())) 'Enter a valid six-digit pincode.',
    if (vendorPhotos < staffVendorPhotoNames.length) 'Add all ${staffVendorPhotoNames.length} photos of the vendor.',
    if (items.isEmpty) 'Add at least one item the vendor sells.',
    for (final (i, item) in items.indexed) ...[
      if (item.libraryItem == null) 'Item ${i + 1}: choose the item.',
      if ((double.tryParse(item.price.text.trim()) ?? 0) <= 0) 'Item ${i + 1}: enter the price.',
      if (item.photos.length < staffItemMinPhotos) 'Item ${i + 1}: add $staffItemMinPhotos or $staffItemMaxPhotos photos.',
    ],
  ];
}

/// What is sent to submitStaffVendor (functions/staff-additions.js).
Map<String, Object> staffVendorRequest({
  required String additionId,
  required String name,
  required String phone,
  required String ownerName,
  required String shopCategory,
  required String address,
  required String pincode,
  required String description,
  required double latitude,
  required double longitude,
  required String gpsAddress,
  required List<StaffItemDraft> items,
}) => {
  'additionId': additionId,
  'vendor': {
    'name': name.trim(), 'phone': phone.trim(), 'ownerName': ownerName.trim(), 'shopCategory': shopCategory.trim(),
    'address': address.trim(), 'pincode': pincode.trim(), 'description': description.trim(),
  },
  'latitude': latitude,
  'longitude': longitude,
  if (gpsAddress.trim().isNotEmpty) 'gpsAddress': gpsAddress.trim(),
  'items': [
    for (final item in items)
      {
        'libraryItemId': item.libraryItem!.id,
        'unitType': item.unitType,
        'quantity': item.quantity,
        'price': double.parse(item.price.text.trim()),
        'photoCount': item.photos.length,
      },
  ],
};

String _newAdditionId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
}

/// Staff > Add > Vendor: the staff member is at the shop. Their GPS is the vendor's location (nothing is added without it) and fills
/// the address and pincode. The vendor's name and phone are required, with 3 photos (the vendor or shop, and two more), and the items
/// the vendor sells: from the admin's library, 1-10 kg or pieces at a price, 2-3 photos each (up to 2 items, the vendor item limit).
/// Nothing is live until the admin approves it.
class FieldAddVendorForm extends StatefulWidget {
  const FieldAddVendorForm({super.key, required this.store, this.locate, this.lookUpAddress, this.findPlace, this.takePhoto});
  final Store store;
  // Test seams: the phone's GPS, the street address, the pincode directory, and taking + uploading one photo (by its name).
  final Future<Position> Function()? locate;
  final Future<ReverseAddress?> Function(double latitude, double longitude)? lookUpAddress;
  final Future<Place?> Function(double latitude, double longitude)? findPlace;
  final Future<Uint8List?> Function(String additionId, String name)? takePhoto;
  @override
  State<FieldAddVendorForm> createState() => _FieldAddVendorFormState();
}

class _FieldAddVendorFormState extends State<FieldAddVendorForm> {
  Store get store => widget.store;
  late final String additionId = _newAdditionId();
  final name = TextEditingController(), phone = TextEditingController(), ownerName = TextEditingController();
  final shopCategory = TextEditingController(), address = TextEditingController(), pincode = TextEditingController();
  final description = TextEditingController();
  final vendorPhotos = <String, Uint8List>{};
  final items = <StaffItemDraft>[StaffItemDraft()];
  Position? position;
  String? locationError;
  bool capturingLocation = true, lookingUpAddress = false, busy = false;
  String gpsAddress = '', gpsPincode = '';
  String? uploading;
  List<String> errors = const [];

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  @override
  void dispose() {
    for (final c in [name, phone, ownerName, shopCategory, address, pincode, description]) {
      c.dispose();
    }
    for (final item in items) {
      item.price.dispose();
    }
    super.dispose();
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message'.replaceFirst('Bad state: ', ''))));

  Future<void> _captureLocation() async {
    setState(() { capturingLocation = true; locationError = null; });
    try {
      final result = await (widget.locate ?? () => currentPosition(action: 'add the vendor at your location'))();
      if (mounted) setState(() { position = result; capturingLocation = false; });
      await _fillFromGps(result);
    } catch (e) {
      if (mounted) setState(() { locationError = '$e'.replaceFirst('Bad state: ', ''); capturingLocation = false; });
    }
  }

  /// The address and pincode of the GPS point; a box the staff member typed into is left alone.
  Future<void> _fillFromGps(Position point) async {
    setState(() => lookingUpAddress = true);
    final gps = await addressForPoint(point.latitude, point.longitude, contactEmail: store.business.text('supportEmail'), lookUp: widget.lookUpAddress, findPlace: widget.findPlace);
    if (!mounted) return;
    setState(() {
      lookingUpAddress = false;
      if (gps.text.isNotEmpty) {
        if (address.text.trim().isEmpty || address.text.trim() == gpsAddress) address.text = gps.text;
        gpsAddress = gps.text;
      }
      if (gps.pincode.isNotEmpty) {
        if (pincode.text.trim().isEmpty || pincode.text.trim() == gpsPincode) pincode.text = gps.pincode;
        gpsPincode = gps.pincode;
      }
    });
  }

  Future<Uint8List?> _take(String photoName) async {
    if (widget.takePhoto != null) return widget.takePhoto!(additionId, photoName);
    final file = await ImagePicker().pickImage(source: kIsWeb ? ImageSource.gallery : ImageSource.camera, maxWidth: 1600, imageQuality: 85);
    if (file == null) return null;
    return store.uploadStaffAdditionPhoto(additionId, photoName, file);
  }

  Future<void> _photo(String photoName, void Function(Uint8List bytes) done) async {
    setState(() => uploading = photoName);
    try {
      final bytes = await _take(photoName);
      if (bytes != null && mounted) setState(() => done(bytes));
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  Future<void> _submit() async {
    final problems = staffVendorErrors(
      name: name.text, phone: phone.text, address: address.text, pincode: pincode.text, hasLocation: position != null,
      vendorPhotos: vendorPhotos.length, items: items,
    );
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      final result = await store.call('submitStaffVendor', staffVendorRequest(
        additionId: additionId, name: name.text, phone: phone.text, ownerName: ownerName.text, shopCategory: shopCategory.text,
        address: address.text, pincode: pincode.text, description: description.text, latitude: position!.latitude, longitude: position!.longitude,
        gpsAddress: gpsAddress, items: items,
      ));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(result['status'] == 'approved' ? 'Live now' : 'Sent for approval'),
          content: Text('${name.text.trim()} ${result['status'] == 'approved' ? 'is live: your additions are approved automatically.' : 'is waiting for the administrator. Nothing is live until it is approved.'}${result['vendorCode'] == null ? '' : '\n\nVendor ID: ${result['vendorCode']}'}'),
          actions: [FilledButton(onPressed: () => Navigator.pop(dialog), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _thumb(Uint8List? bytes, {required String label, required String keyName, required VoidCallback? onTap}) => InkWell(
    key: ValueKey(keyName),
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover)
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(uploading == keyName.replaceFirst('staff-photo-', '') ? Icons.hourglass_top : Icons.add_a_photo_outlined),
              Padding(padding: const EdgeInsets.all(4), child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
            ]),
    ),
  );

  Widget get _locationCard => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Vendor location', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text('Location must be ON. Stand at the shop: your current GPS location is saved as the vendor\'s location and fills in the address.'),
    const SizedBox(height: 8),
    if (capturingLocation) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Capturing your location...')]))
    else if (position != null) ...[
      ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(shops: [Entry('here', {'name': 'Vendor location', 'latitude': position!.latitude, 'longitude': position!.longitude})], height: 160)),
      const SizedBox(height: 8),
      Text('Location captured: ${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'),
      if (lookingUpAddress) const Text('Finding the address of this location...'),
    ] else if (locationError != null)
      Text(locationError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    OutlinedButton.icon(onPressed: capturingLocation ? null : _captureLocation, icon: const Icon(Icons.my_location), label: Text(position != null ? 'Recapture location' : 'Try again')),
  ])));

  void _removeLastItem() {
    final removed = items.removeLast();
    setState(() {});
    // Its price box is still on screen until this frame is drawn; the controller goes after that.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.price.dispose());
  }

  Widget _itemCard(int i, StaffItemDraft item) {
    final library = store.entries('productImageLibrary');
    final categories = libraryCategories(library, store.visible('categories'));
    final choices = item.categoryId == null ? const <Entry>[] : libraryItemsIn(library, item.categoryId!);
    return Card(
      key: ValueKey('staff-item-$i'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Item ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
            if (i > 0 && i == items.length - 1)
              TextButton(key: ValueKey('staff-item-remove-$i'), onPressed: busy ? null : _removeLastItem, child: const Text('Remove')),
          ]),
          DropdownButtonFormField<String>(
            key: ValueKey('staff-item-category-$i-${item.categoryId}'),
            initialValue: item.categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in categories) DropdownMenuItem(value: c.$1, child: Text(c.$2))],
            onChanged: (v) => setState(() {
              item.categoryId = v;
              item.libraryItem = null;
            }),
          ),
          if (categories.isEmpty) const Text('The admin has not added any items yet.'),
          if (item.categoryId != null) ...[
            const SizedBox(height: 8),
            if (choices.isEmpty) const Text('No items in this category yet.'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in choices)
                LibraryItemTile(key: ValueKey('staff-library-$i-${e.id}'), item: e, selected: item.libraryItem?.id == e.id, onTap: () => setState(() => item.libraryItem = e)),
            ]),
          ],
          if (item.libraryItem != null) ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              key: ValueKey('staff-item-unit-$i'),
              segments: const [ButtonSegment(value: 'kg', label: Text('Kg')), ButtonSegment(value: 'pcs', label: Text('Pieces'))],
              selected: {item.unitType},
              onSelectionChanged: (v) => setState(() => item.unitType = v.first),
            ),
            DropdownButtonFormField<int>(
              key: ValueKey('staff-item-quantity-$i-${item.unitType}'),
              initialValue: item.quantity,
              decoration: InputDecoration(labelText: item.unitType == 'kg' ? 'Quantity (kg)' : 'Quantity (pieces)'),
              items: [for (final q in vendorItemQuantities) DropdownMenuItem(value: q, child: Text(vendorItemUnit(item.unitType, q)))],
              onChanged: (v) => setState(() => item.quantity = v ?? 1),
            ),
            TextField(
              key: ValueKey('staff-item-price-$i'),
              controller: item.price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Price for ${vendorItemUnit(item.unitType, item.quantity)} (₹)', hintText: 'e.g. 50'),
            ),
          ],
          const SizedBox(height: 10),
          Text('Photos of the item ($staffItemMinPhotos or $staffItemMaxPhotos)'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var n = 0; n < item.photos.length; n++)
              _thumb(item.photos[n], label: 'Photo ${n + 1}', keyName: 'staff-photo-item${i + 1}_${n + 1}', onTap: busy || uploading != null ? null : () => _photo('item${i + 1}_${n + 1}', (b) => item.photos[n] = b)),
            if (item.photos.length < staffItemMaxPhotos)
              _thumb(null, label: 'Add photo ${item.photos.length + 1}${item.photos.length >= staffItemMinPhotos ? ' (optional)' : ''}', keyName: 'staff-photo-item${i + 1}_${item.photos.length + 1}',
                  onTap: busy || uploading != null ? null : () => _photo('item${i + 1}_${item.photos.length + 1}', (b) => item.photos.add(b))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add a vendor')),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) => Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Fill in the vendor\'s details at the shop. Nothing is shown to customers until the administrator approves it.'),
                const SizedBox(height: 12),
                _locationCard,
                const SizedBox(height: 8),
                TextField(key: const ValueKey('staff-vendor-name'), controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Vendor / shop name (required)')),
                TextField(key: const ValueKey('staff-vendor-phone'), controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Vendor phone number (required)')),
                TextField(key: const ValueKey('staff-vendor-owner'), controller: ownerName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Owner name')),
                TextField(key: const ValueKey('staff-vendor-category'), controller: shopCategory, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Shop category (e.g. Kirana, Vegetables)')),
                TextField(key: const ValueKey('staff-vendor-address'), controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address (from your location)')),
                TextField(key: const ValueKey('staff-vendor-pincode'), controller: pincode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Pincode', counterText: '')),
                TextField(key: const ValueKey('staff-vendor-description'), controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'About the shop')),
                const SizedBox(height: 16),
                const Text('Vendor photos (3)', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('Photo 1 of the vendor or the shop, and two more photos.'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (n, photoName) in staffVendorPhotoNames.indexed)
                    _thumb(vendorPhotos[photoName], label: n == 0 ? 'Vendor / shop photo' : 'Extra photo $n', keyName: 'staff-photo-$photoName',
                        onTap: busy || uploading != null ? null : () => _photo(photoName, (b) => vendorPhotos[photoName] = b)),
                ]),
                const SizedBox(height: 16),
                Text('Items the vendor sells (up to $defaultVendorItemLimit)', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Choose from the items the admin has added, with the quantity and the price. A price stays for $vendorPriceValidHours hours; then you enter a new one in My vendors and services.'),
                for (final (i, item) in items.indexed) _itemCard(i, item),
                if (items.length < defaultVendorItemLimit)
                  OutlinedButton.icon(key: const ValueKey('staff-item-add'), onPressed: busy ? null : () => setState(() => items.add(StaffItemDraft())), icon: const Icon(Icons.add), label: const Text('Add another item')),
                if (errors.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Please fix the following before sending:', style: TextStyle(fontWeight: FontWeight.bold)),
                    for (final e in errors) Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ])),
                const SizedBox(height: 16),
                FilledButton(key: const ValueKey('staff-vendor-submit'), onPressed: busy || uploading != null ? null : _submit, child: Text(busy ? 'Sending...' : 'Send for approval')),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}
