import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart';

import '../data/store.dart';
import '../services/area_lookup.dart';
import '../services/geocoding.dart';
import '../domain/towns.dart';
import '../services/location.dart';
import '../services/strings.dart';
import 'location_picker.dart';
import 'place_search_box.dart';
import 'shared.dart';

/// The "Where are you shopping?" dialog: GPS, a place or pincode from the directory list, the admin's towns, a typed pincode, a
/// place-name search or a pin on the map. Every way ends in ONE place (lib/services/area_lookup.dart): the point the shops, products
/// and offers within the admin's km are measured from, and the area name shown everywhere; the area and the offers change at once.
/// The address field is for delivery only and is never shown as the place.
///
/// The list at the top searches the India Post directory (a town, an area or a pincode); the directory file is fetched when this
/// dialog opens (never with the home page) and cached afterwards. [locate] replaces the GPS position and [atPoint] the place at a
/// point in tests.
Future<void> showLocationPickerDialog(
  BuildContext context,
  Store store, {
  Future<Position> Function()? locate,
  Future<FoundPlace> Function(double latitude, double longitude)? atPoint,
}) async {
  final pin = TextEditingController(text: store.pincode),
      address = TextEditingController(text: store.address);
  Future<FoundPlace> placeAt(double latitude, double longitude) =>
      atPoint?.call(latitude, longitude) ?? placeAtPoint(store, latitude, longitude);
  await showDialog<void>(
    context: context,
    builder: (dialog) {
      Future<void> choose(Future<void> Function() action) async {
        try {
          await action();
          if (dialog.mounted) Navigator.pop(dialog);
        } catch (e) {
          if (dialog.mounted) message(dialog, e);
        }
      }

      final towns = parseServiceTowns(store.business.text('serviceTowns'));
      return AlertDialog(
        title: Text('Where are you shopping?'.tr(context)),
        content: SizedBox(
          // Never request more than actually fits once the default AlertDialog inset is subtracted.
          width: (MediaQuery.sizeOf(context).width - 80).clamp(240, 400),
          // Scrollable: the fields and buttons can exceed a short phone screen, especially with the keyboard open.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Use GPS, or type your area, town or pincode. You see the shops and offers within {km} km.'.tr(context, {
                    'km': kmLabel(store.reachKm),
                  }),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('use-my-location'),
                  onPressed: () => choose(() async {
                    final position = await (locate?.call() ?? currentPosition(action: 'set your shopping location'));
                    if (!exactEnough(position)) {
                      throw StateError('Your exact location could not be found. Type your area, town or pincode instead.');
                    }
                    await savePlace(store, await placeAt(position.latitude, position.longitude), followGps: true, address: address.text.trim());
                  }),
                  icon: const Icon(Icons.my_location),
                  label: Text('Use my location'.tr(dialog)),
                ),
                const SizedBox(height: 12),
                PlaceSearchBox(
                  loadNow: true,
                  onPlace: (place) => choose(() => savePlace(store, placeFromDirectory(store, place), address: address.text.trim())),
                ),
                const SizedBox(height: 12),
                if (towns.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('town-picker'),
                    initialValue: towns.any((t) => t.name == store.town) ? store.town : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Your town'.tr(dialog)),
                    items: [for (final town in towns) DropdownMenuItem(value: town.name, child: Text(town.name))],
                    onChanged: (value) {
                      if (value == null) return;
                      choose(() async => savePlace(store, await placeForTown(store, value), address: address.text.trim()));
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const ValueKey('picker-pincode'),
                  controller: pin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(labelText: 'Six-digit pincode'.tr(context)),
                ),
                TextField(
                  key: const ValueKey('picker-address'),
                  controller: address,
                  decoration: InputDecoration(labelText: 'Address for delivery (optional)'.tr(context)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final place = await showModalBottomSheet<NominatimPlace>(
                      context: dialog,
                      isScrollControlled: true,
                      builder: (_) => PlaceSearchSheet(contactEmail: store.business.text('supportEmail')),
                    );
                    if (place == null) return;
                    await choose(() async => savePlace(store, await placeAt(place.latitude, place.longitude), address: address.text.trim()));
                  },
                  icon: const Icon(Icons.search),
                  label: Text('Search by place name'.tr(context)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final initial = store.located ? LatLng(store.latitude!, store.longitude!) : null;
                    final point = await Navigator.of(dialog).push<LatLng>(
                      MaterialPageRoute(builder: (_) => MapPinPickerPage(initialCenter: initial)),
                    );
                    if (point == null) return;
                    await choose(() async => savePlace(store, await placeAt(point.latitude, point.longitude), address: address.text.trim()));
                  },
                  icon: const Icon(Icons.pin_drop_outlined),
                  label: Text('Drop a pin on map'.tr(context)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text('Later'.tr(context))),
          FilledButton(
            key: const ValueKey('picker-save'),
            onPressed: () => choose(() async {
              final typed = pin.text.trim();
              // The same pincode as the place already chosen: only the delivery address changes (a GPS place is kept).
              if (store.located && typed == store.pincode) return store.setDeliveryAddress(address.text.trim());
              if (!RegExp(r'^\d{6}$').hasMatch(typed)) throw StateError('Enter a valid six-digit pincode.');
              await savePlace(store, await placeForPincode(store, typed), address: address.text.trim());
            }),
            child: Text('Save location'.tr(context)),
          ),
        ],
      );
    },
  );
  // Controllers are disposed after the closing dialog animation completes.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  pin.dispose();
  address.dispose();
}

/// "10" for 10 km, "2.5" for 2.5 km.
String kmLabel(double km) => km == km.roundToDouble() ? '${km.round()}' : km.toStringAsFixed(1);
