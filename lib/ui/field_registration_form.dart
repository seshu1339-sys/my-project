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

/// Returns every reason the registration must not be submitted yet. Mirrors
/// the server-side checks in functions/domain.js's fieldStaffDetails(), the
/// same way vendorApplicationErrors() mirrors vendorApplication().
List<String> fieldStaffRegistrationErrors({
  required String name,
  required String phone,
  required bool hasPhoto,
  required String pincode,
  required bool hasLocation,
}) {
  bool between(String v, int min, int max) => v.trim().length >= min && v.trim().length <= max;
  return [
    if (!between(name, 2, 100)) 'Enter your full name.',
    if (!RegExp(r'^\+?[0-9][0-9 -]{6,17}$').hasMatch(phone.trim())) 'Enter a valid contact phone number.',
    if (!hasPhoto) 'Upload a clear photo of yourself.',
    if (!hasLocation) 'Turn on your location (GPS) and capture it.',
    if (!RegExp(r'^\d{6}$').hasMatch(pincode.trim())) 'Enter a valid six-digit pincode.',
  ];
}

/// What is sent to requestFieldStaffAccess (functions/field-assistant.js).
Map<String, Object> fieldStaffRequest({
  required String name,
  required String phone,
  required double latitude,
  required double longitude,
  required String pincode,
  String gpsAddress = '',
}) => {
  'name': name.trim(),
  'phone': phone.trim(),
  'latitude': latitude,
  'longitude': longitude,
  'pincode': pincode.trim(),
  if (gpsAddress.trim().isNotEmpty) 'gpsAddress': gpsAddress.trim(),
};

/// Shown once, the first time a verified-email user opens the Field Assistant
/// app and no fieldStaff/{uid} doc exists yet. A photo is mandatory — the
/// server (requestFieldStaffAccess) independently refuses to create the
/// pending record without one, the same way vendor registration independently
/// refuses without its two mandatory photos.
/// Registration is by location, like a vendor's: the GPS location is captured when the form opens and its pincode (from the India
/// Post directory) gives the Staff ID its town and pincode (STF-NRPM-116-001). Nothing can be submitted without it.
class FieldRegistrationForm extends StatefulWidget {
  const FieldRegistrationForm({super.key, required this.store, this.displayName = '', this.locate, this.lookUpAddress, this.findPlace});
  final Store store;
  // The name on the signed-in account, to start the name box with.
  final String displayName;
  // Test seams: the phone's GPS, the street address and the pincode directory.
  final Future<Position> Function()? locate;
  final Future<ReverseAddress?> Function(double latitude, double longitude)? lookUpAddress;
  final Future<Place?> Function(double latitude, double longitude)? findPlace;
  @override
  State<FieldRegistrationForm> createState() => _FieldRegistrationFormState();
}

class _FieldRegistrationFormState extends State<FieldRegistrationForm> {
  late final name = TextEditingController(text: widget.displayName);
  final phone = TextEditingController();
  final pincode = TextEditingController();
  Uint8List? photoBytes;
  bool photoReady = false;
  bool uploading = false;
  bool busy = false;
  List<String> errors = const [];
  // The staff member's GPS location, captured when the form opens, and the area and pincode worked out from it.
  Position? position;
  String? locationError;
  bool capturingLocation = true;
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
      final result = await (widget.locate ?? () => currentPosition(action: 'register as field staff'))();
      if (mounted) setState(() { position = result; capturingLocation = false; });
      await _fillFromGps(result);
    } catch (e) {
      if (mounted) setState(() { locationError = '$e'.replaceFirst('Bad state: ', ''); capturingLocation = false; });
    }
  }

  /// The area and pincode of the GPS point (the pincode from the India Post directory, as for a vendor). A pincode the staff member
  /// typed is left alone; one that still shows the earlier GPS value is updated.
  Future<void> _fillFromGps(Position point) async {
    setState(() => lookingUpAddress = true);
    final gps = await addressForPoint(point.latitude, point.longitude, contactEmail: widget.store.business.text('supportEmail'), lookUp: widget.lookUpAddress, findPlace: widget.findPlace);
    if (!mounted) return;
    setState(() {
      lookingUpAddress = false;
      if (gps.text.isNotEmpty) gpsAddress = gps.text;
      if (gps.pincode.isNotEmpty) {
        if (pincode.text.trim().isEmpty || pincode.text.trim() == gpsPincode) pincode.text = gps.pincode;
        gpsPincode = gps.pincode;
      }
    });
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() => uploading = true);
      final bytes = await widget.store.uploadStaffPhoto(file);
      if (!mounted) return;
      setState(() { photoBytes = bytes; photoReady = true; errors = const []; });
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> submit() async {
    final problems = fieldStaffRegistrationErrors(name: name.text, phone: phone.text, hasPhoto: photoReady, pincode: pincode.text, hasLocation: position != null);
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      await widget.store.call(
        'requestFieldStaffAccess',
        fieldStaffRequest(name: name.text, phone: phone.text, latitude: position!.latitude, longitude: position!.longitude, pincode: pincode.text, gpsAddress: gpsAddress),
      );
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget get _locationCard => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Your location', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text('Location must be ON: registration is by location. Your Staff ID is made from the pincode of the place where you register.'),
    const SizedBox(height: 8),
    if (capturingLocation) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Capturing your location...')]))
    else if (position != null) ...[
      ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(shops: [Entry('me', {'name': 'Your location', 'latitude': position!.latitude, 'longitude': position!.longitude})], height: 160)),
      const SizedBox(height: 8),
      Text('Location captured: ${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'),
      if (lookingUpAddress) const Text('Finding the area of this location...')
      else if (gpsAddress.isNotEmpty) Text('Area: $gpsAddress', key: const ValueKey('staff-gps-address')),
    ] else if (locationError != null)
      Text(locationError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const SizedBox(height: 8),
    TextField(key: const ValueKey('staff-pincode'), controller: pincode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Pincode (from your location)', counterText: '')),
    OutlinedButton.icon(onPressed: capturingLocation ? null : _captureLocation, icon: const Icon(Icons.my_location), label: Text(position != null ? 'Recapture location' : 'Try again')),
  ])));

  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Field staff registration', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Complete every field, capture your location and upload a clear photo of yourself, then submit for administrator approval.'),
      const SizedBox(height: 16),
      TextField(key: const ValueKey('staff-name'), controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your full name')),
      TextField(key: const ValueKey('staff-phone'), controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone')),
      const SizedBox(height: 12),
      _locationCard,
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your photo', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('A clear personal photo so the administrator can identify you.'),
        const SizedBox(height: 8),
        if (photoBytes != null)
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photoBytes!, height: 150, fit: BoxFit.cover))
        else
          Container(height: 90, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)), child: Icon(photoReady ? Icons.check_circle : Icons.add_a_photo_outlined)),
        const SizedBox(height: 8),
        Text(uploading ? 'Uploading...' : photoReady ? 'Photo uploaded' : 'Required: not uploaded yet'),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: busy || uploading ? null : () => pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose photo')),
          if (!kIsWeb) OutlinedButton.icon(onPressed: busy || uploading ? null : () => pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo')),
        ]),
      ]))),
      if (errors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Please fix the following before submitting:', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final e in errors) Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      if (position == null && !capturingLocation)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Turn on your location (GPS) and capture it above: you cannot register without it.', key: const ValueKey('staff-location-required'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      FilledButton(key: const ValueKey('staff-submit'), onPressed: busy || uploading ? null : submit, child: Text(busy ? 'Submitting...' : 'Submit for approval')),
    ]),
  ))));

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    pincode.dispose();
    super.dispose();
  }
}
