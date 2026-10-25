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

/// Every reason the provider application must not be submitted yet (the server, functions/providers.js, checks the same).
List<String> providerApplicationErrors({
  required String name,
  required String phone,
  required String? serviceTypeId,
  required String hourlyRate,
  required String address,
  required String pincode,
  required bool hasPhoto,
  required bool hasLocation,
}) {
  final rate = double.tryParse(hourlyRate.trim());
  final n = name.trim().length;
  return [
    if (n < 2 || n > 100) 'Enter your full name.',
    if (!RegExp(r'^\+?[0-9][0-9 -]{6,17}$').hasMatch(phone.trim())) 'Enter a valid mobile number.',
    if (serviceTypeId == null) 'Choose your service.',
    if (rate == null || rate <= 0 || rate > 100000) 'Enter your charge per hour (for example 200).',
    if (address.trim().length < 5) 'Enter your house address.',
    if (!RegExp(r'^\d{6}$').hasMatch(pincode.trim())) 'Enter a valid six-digit pincode.',
    if (!hasPhoto) 'Upload your photo.',
    if (!hasLocation) 'Turn on your location (GPS) and capture it.',
  ];
}

/// The service-provider registration: name, mobile, photo, one service from the admin's list, the charge per hour, and the house
/// address filled from the GPS (location must be on). Sent for the admin's approval. A separate account from vendors.
class ProviderRegistrationForm extends StatefulWidget {
  const ProviderRegistrationForm({super.key, required this.store, required this.email, this.previous, this.locate, this.lookUpAddress, this.findPlace});
  final Store store;
  final String email;
  final Map<String, dynamic>? previous;

  /// For tests: the GPS reading and the address lookups (default: the phone's GPS, OpenStreetMap and the India Post directory).
  final Future<Position> Function()? locate;
  final Future<ReverseAddress?> Function(double latitude, double longitude)? lookUpAddress;
  final Future<Place?> Function(double latitude, double longitude)? findPlace;
  @override
  State<ProviderRegistrationForm> createState() => _ProviderRegistrationFormState();
}

class _ProviderRegistrationFormState extends State<ProviderRegistrationForm> {
  late final name = TextEditingController(text: '${widget.previous?['name'] ?? ''}');
  late final phone = TextEditingController(text: '${widget.previous?['phone'] ?? ''}');
  late final rate = TextEditingController(text: widget.previous?['hourlyRate'] == null ? '' : '${widget.previous!['hourlyRate']}');
  late final address = TextEditingController(text: '${widget.previous?['address'] ?? ''}');
  late final pincode = TextEditingController(text: '${widget.previous?['pincode'] ?? ''}');
  late String? serviceTypeId = widget.previous?['serviceTypeId'] as String?;
  Uint8List? photoBytes;
  late bool photoReady = widget.previous?['photoPath'] != null;
  bool uploading = false, busy = false;
  List<String> errors = const [];
  Position? position;
  String? locationError;
  bool capturingLocation = true, lookingUpAddress = false;
  String gpsAddress = '', gpsPincode = '';

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

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> _captureLocation() async {
    setState(() {
      capturingLocation = true;
      locationError = null;
    });
    try {
      final result = await (widget.locate ?? () => currentPosition(action: 'capture your location'))();
      if (!mounted) return;
      setState(() {
        position = result;
        capturingLocation = false;
        lookingUpAddress = true;
      });
      final gps = await addressForPoint(result.latitude, result.longitude, contactEmail: widget.store.business.text('supportEmail'), lookUp: widget.lookUpAddress, findPlace: widget.findPlace);
      if (!mounted) return;
      setState(() {
        lookingUpAddress = false;
        // A box the provider typed into is left alone; one that still shows the earlier GPS value is updated.
        if (gps.text.isNotEmpty) {
          if (address.text.trim().isEmpty || address.text.trim() == gpsAddress) address.text = gps.text;
          gpsAddress = gps.text;
        }
        if (gps.pincode.isNotEmpty) {
          if (pincode.text.trim().isEmpty || pincode.text.trim() == gpsPincode) pincode.text = gps.pincode;
          gpsPincode = gps.pincode;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          locationError = '$e'.replaceFirst('Bad state: ', '');
          capturingLocation = false;
          lookingUpAddress = false;
        });
      }
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() => uploading = true);
      final bytes = await widget.store.uploadProviderPhoto(file);
      if (mounted) {
        setState(() {
          photoBytes = bytes;
          photoReady = true;
        });
      }
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _submit() async {
    final problems = providerApplicationErrors(
      name: name.text, phone: phone.text, serviceTypeId: serviceTypeId, hourlyRate: rate.text, address: address.text, pincode: pincode.text,
      hasPhoto: photoReady, hasLocation: position != null,
    );
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      await widget.store.registerProvider(
        name: name.text.trim(), phone: phone.text.trim(), serviceTypeId: serviceTypeId!, hourlyRate: double.parse(rate.text.trim()),
        address: address.text.trim(), pincode: pincode.text.trim(), latitude: position!.latitude, longitude: position!.longitude, gpsAddress: gpsAddress,
      );
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = [...widget.store.serviceTypes()]..sort((a, b) => a.text('name').toLowerCase().compareTo(b.text('name').toLowerCase()));
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.previous == null ? 'Service provider registration' : 'Update your service-provider application', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                const Text('Your email is verified. Fill in your details, choose your service and your charge per hour, and submit for the admin\'s approval.'),
                if (widget.previous?['status'] == 'rejected' && '${widget.previous?['decisionReason'] ?? ''}'.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text('Application rejected. Reason: ${widget.previous!['decisionReason']}', style: error)),
                const SizedBox(height: 16),
                InputDecorator(decoration: const InputDecoration(labelText: 'Verified email', border: OutlineInputBorder()), child: Text(widget.email)),
                const SizedBox(height: 12),
                TextField(key: const ValueKey('provider-name'), controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name')),
                TextField(key: const ValueKey('provider-phone'), controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
                DropdownButtonFormField<String>(
                  key: ValueKey('provider-service-$serviceTypeId'),
                  initialValue: types.any((t) => t.id == serviceTypeId) ? serviceTypeId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Your service'),
                  items: [for (final t in types) DropdownMenuItem(value: t.id, child: Text(t.text('name', t.id)))],
                  onChanged: (v) => setState(() => serviceTypeId = v),
                ),
                if (types.isEmpty) const Text('The service list is not available yet. Please try again later.'),
                TextField(
                  key: const ValueKey('provider-rate'),
                  controller: rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Your charge per hour (₹)', hintText: 'e.g. 200'),
                ),
                TextField(
                  key: const ValueKey('provider-address'),
                  controller: address,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'House address', helperText: 'Filled from your GPS location; correct it if needed.'),
                ),
                TextField(key: const ValueKey('provider-pincode'), controller: pincode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Pincode', counterText: '')),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your location', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Text('Location must be ON: registration is by location. Your GPS location is saved as your house location and fills in the address above.'),
                        const SizedBox(height: 8),
                        if (capturingLocation)
                          const Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Capturing your location...')])
                        else if (position != null) ...[
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(shops: [Entry('me', {'name': 'Your location', 'latitude': position!.latitude, 'longitude': position!.longitude})], height: 160)),
                          const SizedBox(height: 8),
                          if (lookingUpAddress) const Text('Finding the address of this location...') else if (gpsAddress.isNotEmpty) Text('Address from GPS: $gpsAddress', key: const ValueKey('provider-gps-address')),
                        ] else if (locationError != null)
                          Text(locationError!, style: error),
                        OutlinedButton.icon(onPressed: capturingLocation ? null : _captureLocation, icon: const Icon(Icons.my_location), label: Text(position != null ? 'Recapture location' : 'Try again')),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your photo', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Text('A clear photo of you. Customers see it on your service once the admin approves.'),
                        const SizedBox(height: 8),
                        if (photoBytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photoBytes!, height: 150, fit: BoxFit.cover)),
                        Text(uploading ? 'Uploading...' : photoReady ? 'Photo uploaded' : 'Required: not uploaded yet'),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(onPressed: busy || uploading ? null : () => _pickPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose photo')),
                            if (!kIsWeb) OutlinedButton.icon(onPressed: busy || uploading ? null : () => _pickPhoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (errors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [const Text('Please fix the following before submitting:', style: TextStyle(fontWeight: FontWeight.bold)), for (final e in errors) Text('• $e', style: error)],
                    ),
                  ),
                if (position == null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Turn on your location (GPS) and capture it above: you cannot register without it.', key: const ValueKey('provider-location-required'), style: error)),
                const SizedBox(height: 16),
                FilledButton(key: const ValueKey('provider-submit'), onPressed: busy || uploading ? null : _submit, child: Text(busy ? 'Submitting...' : 'Submit for approval')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
