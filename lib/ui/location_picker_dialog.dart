import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart';

import '../data/store.dart';
import '../services/geocoding.dart';
import '../domain/towns.dart';
import '../services/location.dart';
import '../services/location_town.dart';
import '../services/strings.dart';
import 'location_picker.dart';
import 'place_search_box.dart';
import 'shared.dart';

/// The "Where are you shopping?" dialog — pincode/address entry, GPS,
/// place-name search, or drop-a-pin, all writing through `store.setLocation`.
/// Extracted out of storefront.dart so the storefront shell stays a thin
/// composition root.
///
/// The top of the dialog is a live search over the Andhra Pradesh/Telangana
/// places directory (a town name or a pincode); the directory file is fetched
/// when this dialog opens (never with the home page) and cached afterwards.
/// [locate] replaces the GPS lookup in tests.
Future<void> showLocationPickerDialog(
  BuildContext context,
  Store store, {
  Future<Position> Function()? locate,
}) async {
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
              const SizedBox(height: 12),
              PlaceSearchBox(
                loadNow: true,
                onPlace: (place) async {
                  // Chosen from the list: pincode mode (no GPS coordinates), exactly
                  // like typing the pincode, plus the town/district/state for offers.
                  await store.setLocation(
                    place.pincode,
                    place.label,
                    town: place.town,
                    district: place.district,
                    state: place.state,
                  );
                  if (dialog.mounted) Navigator.pop(dialog);
                },
              ),
              const SizedBox(height: 12),
              if (parseServiceTowns(store.business.text('serviceTowns'))
                  .isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('town-picker'),
                  initialValue:
                      parseServiceTowns(store.business.text('serviceTowns'))
                          .any((t) => t.name == store.town)
                      ? store.town
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Your town'.tr(dialog),
                  ),
                  items: [
                    for (final town in parseServiceTowns(
                      store.business.text('serviceTowns'),
                    ))
                      DropdownMenuItem(value: town.name, child: Text(town.name)),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    await store.setLocation(
                      store.pincode,
                      store.address,
                      lat: store.latitude,
                      lng: store.longitude,
                      town: value,
                    );
                    if (dialog.mounted) Navigator.pop(dialog);
                  },
                ),
                const SizedBox(height: 12),
              ],
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
                    final position = await (locate?.call() ??
                        currentPosition(action: 'set your shopping location'));
                    final value = pin.text.trim();
                    if (value.isNotEmpty &&
                        !RegExp(r'^\d{6}$').hasMatch(value)) {
                      throw StateError(
                        'Enter a valid pincode or clear it before using GPS.',
                      );
                    }
                    // The nearest town from the directory's own coordinates
                    // (works offline once cached); the reverse lookup only if
                    // the directory is unavailable or the customer is outside it.
                    final nearest = await nearestPlaceFor(
                      position.latitude,
                      position.longitude,
                    );
                    await store.setLocation(
                      value.isNotEmpty ? value : (nearest?.pincode ?? ''),
                      address.text.trim().isNotEmpty
                          ? address.text.trim()
                          : (nearest?.label ?? 'Current GPS location'),
                      lat: position.latitude,
                      lng: position.longitude,
                      town:
                          nearest?.town ??
                          await townForPoint(
                            store,
                            position.latitude,
                            position.longitude,
                          ),
                      district: nearest?.district,
                      state: nearest?.state,
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
                label: Text('Use my location'.tr(dialog)),
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
                    town: townForPlace(store, place),
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
                    town: await townForPoint(
                      store,
                      point.latitude,
                      point.longitude,
                    ),
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
