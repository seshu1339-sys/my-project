import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../data/store.dart';
import '../services/geocoding.dart';
import '../services/location.dart';
import 'location_picker.dart';
import 'shared.dart';

/// The "Where are you shopping?" dialog — pincode/address entry, GPS,
/// place-name search, or drop-a-pin, all writing through `store.setLocation`.
/// Extracted out of storefront.dart so the storefront shell stays a thin
/// composition root; behavior is unchanged from the original inline version.
Future<void> showLocationPickerDialog(BuildContext context, Store store) async {
  final pin = TextEditingController(text: store.pincode),
      address = TextEditingController(text: store.address);
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Where are you shopping?'),
      content: SizedBox(
        // Never request more than actually fits once the default AlertDialog inset is subtracted.
        width: (MediaQuery.sizeOf(context).width - 80).clamp(240, 400),
        // Scrollable like the Office dialog below — this content (2 text
        // fields + 3 buttons + description) can exceed the viewport height
        // on a short mobile screen, especially once the on-screen keyboard
        // opens for the pincode field.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Set your pincode for local prices, or use GPS to find shops within their service radius.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Six-digit pincode',
                ),
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(
                  labelText: 'Area / address (optional)',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final position = await currentPosition(
                      action: 'set your shopping location',
                    );
                    final value = pin.text.trim();
                    if (value.isNotEmpty &&
                        !RegExp(r'^\d{6}$').hasMatch(value)) {
                      throw StateError(
                        'Enter a valid pincode or clear it before using GPS.',
                      );
                    }
                    await store.setLocation(
                      value,
                      address.text.trim().isEmpty
                          ? 'Current GPS location'
                          : address.text.trim(),
                      lat: position.latitude,
                      lng: position.longitude,
                    );
                    if (dialog.mounted) {
                      Navigator.pop(dialog);
                    }
                  } catch (e) {
                    if (dialog.mounted) {
                      message(dialog, e);
                    }
                  }
                },
                icon: const Icon(Icons.my_location),
                label: const Text('Use my current location'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final place = await showModalBottomSheet<NominatimPlace>(
                    context: dialog,
                    isScrollControlled: true,
                    builder: (_) => PlaceSearchSheet(
                      contactEmail: store.business.text('supportEmail'),
                    ),
                  );
                  if (place == null) return;
                  await store.setLocation(
                    store.pincode,
                    place.displayName,
                    lat: place.latitude,
                    lng: place.longitude,
                  );
                  if (dialog.mounted) Navigator.pop(dialog);
                },
                icon: const Icon(Icons.search),
                label: const Text('Search by place name'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final initial =
                      store.latitude != null && store.longitude != null
                      ? LatLng(store.latitude!, store.longitude!)
                      : null;
                  final point = await Navigator.of(dialog).push<LatLng>(
                    MaterialPageRoute(
                      builder: (_) => MapPinPickerPage(initialCenter: initial),
                    ),
                  );
                  if (point == null) return;
                  await store.setLocation(
                    store.pincode,
                    'Pinned location',
                    lat: point.latitude,
                    lng: point.longitude,
                  );
                  if (dialog.mounted) Navigator.pop(dialog);
                },
                icon: const Icon(Icons.pin_drop_outlined),
                label: const Text('Drop a pin on map'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () async {
            if (!RegExp(r'^\d{6}$').hasMatch(pin.text.trim())) {
              message(dialog, 'Enter a valid six-digit pincode');
              return;
            }
            await store.setLocation(pin.text.trim(), address.text.trim());
            if (dialog.mounted) {
              Navigator.pop(dialog);
            }
          },
          child: const Text('Save location'),
        ),
      ],
    ),
  );
  // Controllers are disposed after the closing dialog animation completes.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  pin.dispose();
  address.dispose();
}
