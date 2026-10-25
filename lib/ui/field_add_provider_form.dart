import 'dart:math';

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

/// Photos of the provider's work: at least 2, at most 3 (work_1..3).
const staffWorkMinPhotos = 2, staffWorkMaxPhotos = 3;

/// Every reason the provider cannot be added yet. Mirrors staffProviderDetails() in functions/staff-additions.js.
List<String> staffProviderErrors({
  required String name,
  required String phone,
  required String hourlyRate,
  required String pincode,
  required bool hasLocation,
  required int workPhotos,
}) {
  final rate = double.tryParse(hourlyRate.trim());
  return [
    if (!hasLocation) 'Turn on your location (GPS) and capture it: the provider is added at your location.',
    if (name.trim().length < 2 || name.trim().length > 100) "Enter the provider's name.",
    if (!RegExp(r'^\+?[0-9][0-9 -]{6,17}$').hasMatch(phone.trim())) "Enter the provider's phone number.",
    if (rate == null || rate <= 0 || rate > 100000) 'Enter the charge per hour (for example 200).',
    if (!RegExp(r'^\d{6}$').hasMatch(pincode.trim())) 'Enter a valid six-digit pincode.',
    if (workPhotos < staffWorkMinPhotos) 'Add $staffWorkMinPhotos or $staffWorkMaxPhotos photos of their work.',
  ];
}

/// What is sent to submitStaffProvider (functions/staff-additions.js).
Map<String, Object> staffProviderRequest({
  required String additionId,
  required String name,
  required String phone,
  required String address,
  required String pincode,
  required String serviceTypeId,
  required String hourlyRate,
  required double latitude,
  required double longitude,
  required String gpsAddress,
  required int photoCount,
}) => {
  'additionId': additionId,
  'provider': {'name': name.trim(), 'phone': phone.trim(), 'address': address.trim(), 'pincode': pincode.trim()},
  'serviceTypeId': serviceTypeId,
  'hourlyRate': double.parse(hourlyRate.trim()),
  'latitude': latitude,
  'longitude': longitude,
  if (gpsAddress.trim().isNotEmpty) 'gpsAddress': gpsAddress.trim(),
  'photoCount': photoCount,
};

String _newAdditionId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
}

/// Staff > Add > Services > (a service): a service provider (a plumber, a tutor, ...) added by a staff member where the provider is.
/// The staff member's GPS is the provider's location (nothing is added without it); the name and phone are required, with the charge
/// per hour and 2-3 photos of their work. Customers later see the town and an approximate location only. Nothing is live until the
/// admin approves it.
class FieldAddProviderForm extends StatefulWidget {
  const FieldAddProviderForm({super.key, required this.store, required this.serviceType, this.locate, this.lookUpAddress, this.findPlace, this.takePhoto});
  final Store store;
  final Entry serviceType;
  // Test seams: the phone's GPS, the street address, the pincode directory, and taking + uploading one photo (by its name).
  final Future<Position> Function()? locate;
  final Future<ReverseAddress?> Function(double latitude, double longitude)? lookUpAddress;
  final Future<Place?> Function(double latitude, double longitude)? findPlace;
  final Future<Uint8List?> Function(String additionId, String name)? takePhoto;
  @override
  State<FieldAddProviderForm> createState() => _FieldAddProviderFormState();
}

class _FieldAddProviderFormState extends State<FieldAddProviderForm> {
  Store get store => widget.store;
  late final String additionId = _newAdditionId();
  final name = TextEditingController(), phone = TextEditingController(), rate = TextEditingController();
  final address = TextEditingController(), pincode = TextEditingController();
  final photos = <Uint8List>[];
  Position? position;
  String? locationError, uploading;
  bool capturingLocation = true, lookingUpAddress = false, busy = false;
  String gpsAddress = '', gpsPincode = '';
  List<String> errors = const [];

  String get serviceName => widget.serviceType.text('name', 'service');

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  @override
  void dispose() {
    for (final c in [name, phone, rate, address, pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message'.replaceFirst('Bad state: ', ''))));

  Future<void> _captureLocation() async {
    setState(() { capturingLocation = true; locationError = null; });
    try {
      final result = await (widget.locate ?? () => currentPosition(action: 'add the provider at your location'))();
      if (mounted) setState(() { position = result; capturingLocation = false; });
      await _fillFromGps(result);
    } catch (e) {
      if (mounted) setState(() { locationError = '$e'.replaceFirst('Bad state: ', ''); capturingLocation = false; });
    }
  }

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

  Future<void> _photo(int index) async {
    final photoName = 'work_${index + 1}';
    setState(() => uploading = photoName);
    try {
      Uint8List? bytes;
      if (widget.takePhoto != null) {
        bytes = await widget.takePhoto!(additionId, photoName);
      } else {
        final file = await ImagePicker().pickImage(source: kIsWeb ? ImageSource.gallery : ImageSource.camera, maxWidth: 1600, imageQuality: 85);
        if (file != null) bytes = await store.uploadStaffAdditionPhoto(additionId, photoName, file);
      }
      if (bytes != null && mounted) setState(() => index < photos.length ? photos[index] = bytes! : photos.add(bytes!));
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  Future<void> _submit() async {
    final problems = staffProviderErrors(name: name.text, phone: phone.text, hourlyRate: rate.text, pincode: pincode.text, hasLocation: position != null, workPhotos: photos.length);
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      final result = await store.call('submitStaffProvider', staffProviderRequest(
        additionId: additionId, name: name.text, phone: phone.text, address: address.text, pincode: pincode.text, serviceTypeId: widget.serviceType.id,
        hourlyRate: rate.text, latitude: position!.latitude, longitude: position!.longitude, gpsAddress: gpsAddress, photoCount: photos.length,
      ));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(result['status'] == 'approved' ? 'Live now' : 'Sent for approval'),
          content: Text('${name.text.trim()} ($serviceName) ${result['status'] == 'approved' ? 'is live: your additions are approved automatically.' : 'is waiting for the administrator. Nothing is live until it is approved.'}${result['providerCode'] == null ? '' : '\n\nProvider ID: ${result['providerCode']}'}'),
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

  Widget _thumb(int index) {
    final bytes = index < photos.length ? photos[index] : null;
    final photoName = 'work_${index + 1}';
    return InkWell(
      key: ValueKey('staff-photo-$photoName'),
      onTap: busy || uploading != null ? null : () => _photo(index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover)
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(uploading == photoName ? Icons.hourglass_top : Icons.add_a_photo_outlined),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('Add photo ${index + 1}${index >= staffWorkMinPhotos ? ' (optional)' : ''}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                ),
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Add a $serviceName')),
    body: Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Fill in the details where the $serviceName works. Nothing is shown to customers until the administrator approves it.'),
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Location', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('Location must be ON. Your current GPS location is saved as the provider\'s location. Customers see only the town and an approximate location.'),
                const SizedBox(height: 8),
                if (capturingLocation) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Capturing your location...')]))
                else if (position != null) ...[
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(shops: [Entry('here', {'name': 'Provider location', 'latitude': position!.latitude, 'longitude': position!.longitude})], height: 150)),
                  const SizedBox(height: 8),
                  Text('Location captured: ${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'),
                  if (lookingUpAddress) const Text('Finding the address of this location...'),
                ] else if (locationError != null)
                  Text(locationError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                OutlinedButton.icon(onPressed: capturingLocation ? null : _captureLocation, icon: const Icon(Icons.my_location), label: Text(position != null ? 'Recapture location' : 'Try again')),
              ]))),
              const SizedBox(height: 8),
              InputDecorator(decoration: const InputDecoration(labelText: 'Service'), child: Text(serviceName, key: const ValueKey('staff-provider-service'))),
              TextField(key: const ValueKey('staff-provider-name'), controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Provider name (required)')),
              TextField(key: const ValueKey('staff-provider-phone'), controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Provider phone number (required)')),
              TextField(key: const ValueKey('staff-provider-rate'), controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Charge per hour (₹, required)', hintText: 'e.g. 250')),
              TextField(key: const ValueKey('staff-provider-address'), controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address (from your location; not shown to customers)')),
              TextField(key: const ValueKey('staff-provider-pincode'), controller: pincode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Pincode', counterText: '')),
              const SizedBox(height: 12),
              Text('Photos of their work ($staffWorkMinPhotos or $staffWorkMaxPhotos)', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < min(photos.length + 1, staffWorkMaxPhotos); i++) _thumb(i)]),
              if (errors.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Please fix the following before sending:', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final e in errors) Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ])),
              const SizedBox(height: 16),
              FilledButton(key: const ValueKey('staff-provider-submit'), onPressed: busy || uploading != null ? null : _submit, child: Text(busy ? 'Sending...' : 'Send for approval')),
            ]),
          ),
        ),
      ),
    ),
  );
}
