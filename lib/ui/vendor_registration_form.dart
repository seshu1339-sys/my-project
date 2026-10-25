import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/places.dart';
import '../services/geocoding.dart';
import '../services/gps_address.dart';
import '../services/location.dart';
import 'shop_map.dart';

/// Returns every reason the registration must not be submitted yet. Mirrors the
/// server-side checks in functions/domain.js so nothing incomplete is sent.
List<String> vendorApplicationErrors({
  required String ownerName,
  required String phone,
  required String shopName,
  required String shopCategory,
  required String address,
  required String pincode,
  required String description,
  required bool hasVendorPhoto,
  required bool hasShopPhoto,
  required bool hasLocation,
}) {
  bool between(String v, int min, int max) => v.trim().length >= min && v.trim().length <= max;
  return [
    if (!between(ownerName, 2, 100)) "Enter the owner's full name.",
    if (!RegExp(r'^\+?[0-9][0-9 -]{6,17}$').hasMatch(phone.trim())) 'Enter a valid contact phone number.',
    if (!between(shopName, 2, 120)) 'Enter the shop name.',
    if (!between(shopCategory, 2, 80)) 'Enter the shop category.',
    if (!between(address, 5, 500)) 'Enter the shop address.',
    if (!RegExp(r'^\d{6}$').hasMatch(pincode.trim())) 'Enter a valid six-digit pincode.',
    if (!between(description, 10, 1000)) 'Describe the shop (at least 10 characters).',
    if (!hasVendorPhoto) 'Upload a clear personal photo of the vendor.',
    if (!hasShopPhoto) 'Upload a photo of the actual shop.',
    if (!hasLocation) "Capture the shop's GPS location.",
  ];
}

/// The full vendor + shop registration. Shown only after the email is verified,
/// and it cannot be submitted until every field and both photos are provided.
class VendorRegistrationForm extends StatefulWidget {
  const VendorRegistrationForm({super.key, required this.store, required this.email, this.previous, this.locate, this.lookUpAddress, this.findPlace});
  final Store store;
  final String email;
  final Map<String, dynamic>? previous;
  /// For tests: the GPS reading and the address lookup (default: the phone's GPS and OpenStreetMap).
  final Future<Position> Function()? locate;
  final Future<ReverseAddress?> Function(double latitude, double longitude)? lookUpAddress;
  final Future<Place?> Function(double latitude, double longitude)? findPlace;
  @override
  State<VendorRegistrationForm> createState() => _VendorRegistrationFormState();
}

class _VendorRegistrationFormState extends State<VendorRegistrationForm> {
  late final ownerName = TextEditingController(text: '${widget.previous?['ownerName'] ?? ''}');
  late final phone = TextEditingController(text: '${widget.previous?['phone'] ?? ''}');
  late final shopName = TextEditingController(text: '${widget.previous?['name'] ?? ''}');
  late final shopCategory = TextEditingController(text: '${widget.previous?['shopCategory'] ?? ''}');
  late final address = TextEditingController(text: '${widget.previous?['address'] ?? ''}');
  late final pincode = TextEditingController(text: '${widget.previous?['pincode'] ?? ''}');
  late final description = TextEditingController(text: '${widget.previous?['description'] ?? ''}');
  Uint8List? vendorBytes, shopBytes;
  // A rejected applicant may keep the photos already on file, or replace them.
  late bool vendorReady = widget.previous?['vendorPhotoPath'] != null;
  late bool shopReady = widget.previous?['shopPhotoPath'] != null;
  String? uploading;
  List<String> errors = const [];
  bool busy = false;
  // The shop's current GPS location, captured automatically when this form opens. Always captured
  // fresh (never pre-filled from a previous rejected attempt) so it reflects where the vendor is now.
  Position? position;
  String? locationError;
  bool capturingLocation = true;
  // The address and pincode worked out from the GPS. They fill the address and pincode boxes (unless the vendor typed something
  // else), and the address is sent along so the admin can compare.
  String gpsAddress = '', gpsPincode = '';
  bool lookingUpAddress = false;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  Future<void> _captureLocation() async {
    setState(() { capturingLocation = true; locationError = null; });
    try {
      final result = await (widget.locate ?? () => currentPosition(action: "capture your shop's location"))();
      if (mounted) setState(() { position = result; capturingLocation = false; });
      await _fillAddressFromGps(result);
    } catch (e) {
      if (mounted) setState(() { locationError = '$e'.replaceFirst('Bad state: ', ''); capturingLocation = false; });
    }
  }

  /// Fills the address and pincode from the GPS point: the street address from OpenStreetMap, the pincode from the India Post directory
  /// (OpenStreetMap's postcodes are often wrong here; the directory is also what the Vendor ID uses). A box the vendor has typed into
  /// is left alone; one that still shows the earlier GPS value is updated.
  Future<void> _fillAddressFromGps(Position point) async {
    setState(() => lookingUpAddress = true);
    final gps = await addressForPoint(point.latitude, point.longitude, contactEmail: widget.store.business.text('supportEmail'), lookUp: widget.lookUpAddress, findPlace: widget.findPlace);
    if (!mounted) return;
    setState(() {
      lookingUpAddress = false;
      final pin = gps.pincode, text = gps.text;
      if (text.isNotEmpty) {
        if (address.text.trim().isEmpty || address.text.trim() == gpsAddress) address.text = text;
        gpsAddress = text;
      }
      if (pin.isNotEmpty) {
        if (pincode.text.trim().isEmpty || pincode.text.trim() == gpsPincode) pincode.text = pin;
        gpsPincode = pin;
      }
    });
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> pick(String kind, ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() => uploading = kind);
      final bytes = await widget.store.uploadApplicationPhoto(kind, file);
      if (!mounted) return;
      setState(() {
        if (kind == 'vendorPhoto') { vendorBytes = bytes; vendorReady = true; } else { shopBytes = bytes; shopReady = true; }
        errors = const [];
      });
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  Future<void> submit() async {
    final problems = vendorApplicationErrors(
      ownerName: ownerName.text, phone: phone.text, shopName: shopName.text, shopCategory: shopCategory.text,
      address: address.text, pincode: pincode.text, description: description.text,
      hasVendorPhoto: vendorReady, hasShopPhoto: shopReady, hasLocation: position != null,
    );
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      await widget.store.registerVendor(
        ownerName: ownerName.text.trim(), phone: phone.text.trim(), name: shopName.text.trim(), shopCategory: shopCategory.text.trim(),
        address: address.text.trim(), pincode: pincode.text.trim(), description: description.text.trim(),
        latitude: position!.latitude, longitude: position!.longitude, gpsAddress: gpsAddress,
      );
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _photo({required String kind, required String title, required String hint, required Uint8List? bytes, required bool ready}) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    Text(hint),
    const SizedBox(height: 8),
    if (bytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, height: 150, fit: BoxFit.cover))
    else Container(height: 90, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)), child: Icon(ready ? Icons.check_circle : Icons.add_a_photo_outlined)),
    const SizedBox(height: 8),
    Text(uploading == kind ? 'Uploading...' : ready ? 'Photo uploaded' : 'Required: not uploaded yet'),
    Wrap(spacing: 8, children: [
      OutlinedButton.icon(onPressed: busy || uploading != null ? null : () => pick(kind, ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(kind == 'vendorPhoto' ? 'Choose vendor photo' : 'Choose shop photo')),
      if (!kIsWeb) OutlinedButton.icon(onPressed: busy || uploading != null ? null : () => pick(kind, ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: Text(kind == 'vendorPhoto' ? 'Take vendor photo' : 'Take shop photo')),
    ]),
  ])));

  Widget get _locationCard => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Shop location', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text('Location must be ON: registration is by location. Your current GPS location is captured automatically, saved as your shop\'s location, and fills in the shop address below.'),
    const SizedBox(height: 8),
    if (capturingLocation) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Capturing your location...')]))
    else if (position != null) ...[
      ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(shops: [Entry('me', {'name': 'Your location', 'latitude': position!.latitude, 'longitude': position!.longitude})], height: 160)),
      const SizedBox(height: 8),
      Text('Location captured: ${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'),
      if (lookingUpAddress) const Text('Finding the address of this location...')
      else if (gpsAddress.isNotEmpty) Text('Address from GPS: $gpsAddress', key: const ValueKey('gps-address')),
    ] else if (locationError != null)
      Text(locationError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: capturingLocation ? null : _captureLocation, icon: const Icon(Icons.my_location), label: Text(position != null ? 'Recapture location' : 'Try again')),
  ])));

  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.previous == null ? 'Vendor registration' : 'Update your vendor application', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Your email is verified. Complete every field, capture your shop location and upload both photos, then submit for office approval.'),
      if (widget.previous?['decisionReason'] != null && widget.previous?['status'] == 'rejected') Padding(padding: const EdgeInsets.only(top: 8), child: Text('Application rejected. Administrator reason: ${widget.previous!['decisionReason']}', style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      InputDecorator(decoration: const InputDecoration(labelText: 'Verified email', border: OutlineInputBorder()), child: Text(widget.email)),
      const SizedBox(height: 12),
      TextField(controller: ownerName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Owner full name')),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone')),
      TextField(controller: shopName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Shop name')),
      TextField(controller: shopCategory, decoration: const InputDecoration(labelText: 'Shop category', hintText: 'For example Grocery, Hardware')),
      TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Shop address', helperText: 'Filled from your GPS location; correct it if needed.')),
      TextField(controller: pincode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Pincode', counterText: '')),
      TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Shop description')),
      const SizedBox(height: 12),
      _locationCard,
      const SizedBox(height: 12),
      _photo(kind: 'vendorPhoto', title: 'Vendor photo', hint: 'A clear personal photo of the vendor (owner).', bytes: vendorBytes, ready: vendorReady),
      _photo(kind: 'shopPhoto', title: 'Shop photo', hint: 'A separate photo of the actual shop.', bytes: shopBytes, ready: shopReady),
      if (errors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Please fix the following before submitting:', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final e in errors) Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      const SizedBox(height: 16),
      if (position == null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Turn on your location (GPS) and capture it above: you cannot register without it.', key: const ValueKey('location-required'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
      FilledButton(onPressed: busy || uploading != null ? null : submit, child: Text(busy ? 'Submitting...' : 'Submit for approval')),
    ]),
  ))));

  @override
  void dispose() {
    for (final c in [ownerName, phone, shopName, shopCategory, address, pincode, description]) { c.dispose(); }
    super.dispose();
  }
}
