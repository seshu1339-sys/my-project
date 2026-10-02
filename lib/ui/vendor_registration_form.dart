import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/location.dart';
import 'shop_map.dart';
import 'vendor_page.dart';

/// The full vendor + shop registration. Shown only after the email is verified,
/// and it cannot be submitted until every field and both photos are provided.
class VendorRegistrationForm extends StatefulWidget {
  const VendorRegistrationForm({super.key, required this.store, required this.email, this.previous});
  final Store store;
  final String email;
  final Map<String, dynamic>? previous;
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

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  Future<void> _captureLocation() async {
    setState(() { capturingLocation = true; locationError = null; });
    try {
      final result = await currentPosition(action: "capture your shop's location");
      if (mounted) setState(() { position = result; capturingLocation = false; });
    } catch (e) {
      if (mounted) setState(() { locationError = '$e'.replaceFirst('Bad state: ', ''); capturingLocation = false; });
    }
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
        latitude: position!.latitude, longitude: position!.longitude,
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
    const Text('Your current GPS location is captured automatically and required to register.'),
    const SizedBox(height: 8),
    if (capturingLocation) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Capturing your location...')]))
    else if (position != null) ...[
      ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(shops: [Entry('me', {'name': 'Your location', 'latitude': position!.latitude, 'longitude': position!.longitude})], height: 160)),
      const SizedBox(height: 8),
      Text('Location captured: ${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'),
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
      TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Shop address')),
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
      FilledButton(onPressed: busy || uploading != null ? null : submit, child: Text(busy ? 'Submitting...' : 'Submit for approval')),
    ]),
  ))));

  @override
  void dispose() {
    for (final c in [ownerName, phone, shopName, shopCategory, address, pincode, description]) { c.dispose(); }
    super.dispose();
  }
}
