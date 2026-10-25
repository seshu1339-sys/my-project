import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/catalog.dart';
import '../domain/radius.dart';
import 'admin_fields.dart';
import 'color_picker_field.dart';
import '../domain/towns.dart';
import 'geo_target_picker.dart';
import 'location_target_field.dart';
import 'reset_confirmation.dart';
import 'shared.dart';

// Matches layout_editor.dart's own _kindOf rule for the numbered elements'
// forms -- any key ending in "Color" gets the same visual swatch picker
// there, not a raw "#RRGGBB" text box. Applied here too so promotions'
// and the Scrolling Text Settings' color fields (textColor/backgroundColor/
// borderColor) get it as well, instead of just the numbered elements.
bool _isColorField(String key) => key.endsWith('Color');

/// Whether a saved value and the form's value are the same, to write only what the form changed. A saved record can hold values
/// that are not plain JSON (a Firestore Timestamp, a GeoPoint, a DateTime): those are compared by their text instead of failing
/// with "Converting object to an encodable object failed".
bool sameFieldValue(Object? a, Object? b) {
  Object? plain(Object? o) => o is DateTime ? o.toUtc().toIso8601String() : o.toString();
  return jsonEncode(a, toEncodable: plain) == jsonEncode(b, toEncodable: plain);
}
const _fontWeightOptions = <String, String>{
  '400': 'Normal',
  '500': 'Medium',
  '600': 'Semi-bold',
  '700': 'Bold',
  '800': 'Extra bold',
};

/// A stored UTC time shown as the admin's local time (the form's own format,
/// which is read back as local time and saved as UTC again).
String _localTime(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  return parsed.toLocal().toIso8601String().split('.').first;
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.store,
    required this.collection,
    this.entry,
    this.embedded = false,
    this.initialPlacement,
  });
  // A new promotion starts with this placement (carousel, box, ad, ticker); the default is carousel.
  final String? initialPlacement;
  final Store store;
  final String collection;
  final Entry? entry;
  // True when the form is shown inside a Settings section (Business Profile, Theme, Scrolling Text): no title bar of its own,
  // and saving stays on the form instead of closing it.
  final bool embedded;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers;
  bool active = true, busy = false;
  // Set only once the geo-target picker is actually used this session; null
  // means "leave whatever shape data this promotion already has untouched"
  // (the spread in save() below already carries that forward).
  String? pickedShape;
  Map<String, double>? pickedRectangle;
  List<Map<String, double>>? pickedPolygon;
  final numeric = {
    'price',
    'compareAtPrice',
    'stock',
    'order',
    'latitude',
    'longitude',
    'radiusKm',
    'targetLatitude',
    'targetLongitude',
    'targetRadiusKm',
    'searchRadiusDefaultKm',
    'searchRadiusMaxKm',
    'vendorPhotoLimit',
    'fieldPhotoLimit',
    'quickItemsPerDayStaff',
    'quickItemsPerDayVendor',
    'deliveryFee',
    'freeDeliveryAbove',
    'width',
    'height',
    'fontSize',
    'fontWeight',
    'animationSpeed',
    'displayDuration',
    'speed',
    'padding',
    'borderWidth',
    'radius',
    'shadow',
    'brightness',
    'opacity',
    'spacing',
    'animationMs',
    'stopAfter',
    'exclusiveExpiryNoticeDays',
    'storageWarningGb',
  };
  @override
  void initState() {
    super.initState();
    active = widget.entry?.active ?? true;
    controllers = fields[widget.collection]!.map((key, label) {
      final value = widget.entry?.data[key];
      final text = key == 'translations' && value is Map
          ? value.entries.map((e) => '${e.key}=${e.value}').join('\n')
          : key == 'prices' && value is Map
          ? value.entries.map((e) => '${e.key}=${e.value}').join('\n')
          : key == 'images' && value is List
          ? value.join('\n')
          : (key == 'startsAt' || key == 'endsAt') &&
                value is String &&
                value.isNotEmpty
          ? _localTime(value)
          : value?.toString() ??
                ({
                      'stock': '10',
                      'order': '0',
                      'price': '',
                      'radiusKm': widget.collection == 'promotions' ? '' : '10',
                      'searchRadiusPresetsKm': '2,5,10,25,50',
                      'searchRadiusDefaultKm': '10',
                      'searchRadiusMaxKm': '50',
                      'vendorPhotoLimit': '2',
                      'fieldPhotoLimit': '2',
                      'supportEmail': 'info@locamarket.in',
                      'websiteUrl': 'https://locamarket.in',
                      'kind': 'product',
                      'placement': widget.initialPlacement ?? 'carousel',
                      'width': '260',
                      'height': '280',
                      'fontSize': '12',
                      'fontWeight': '400',
                      'speed': '70',
                      'padding': '9',
                      'direction': 'rtl',
                      'radius': '20',
                      'shadow': '0',
                      'brightness': '1',
                      'opacity': '1',
                      'spacing': '16',
                      'animationMs': '6000',
                      'stopAfter': '0',
                      'scrollEnabled': 'false',
                      'position': 'start',
                      'animationSpeed': '600',
                      'displayDuration': '6000',
                      'section': 'header',
                      'borderWidth': '0',
                      'name': key == 'scrollingText'
                          ? 'Scrolling text'
                          : key == 'theme'
                          ? 'Theme'
                          : null,
                      'mode': 'light',
                    }[key] ??
                    '');
      return MapEntry(key, TextEditingController(text: text));
    });
    // The Theme record was saved without a name before, which made its form refuse to save ("Enter a name"): give it one.
    if (widget.collection == 'theme' && controllers['name']!.text.trim().isEmpty) controllers['name']!.text = 'Theme';
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The common radius (same rule for Ads and Today's Offers): the radius must be one of the fixed options, the centre is the chosen shop's saved
  /// location (copied here), and the area may not already be full (Settings > Ads > maximum per area).
  void _applyRadius(Map<String, dynamic> data) {
    final km = (data['radiusKm'] as num?)?.toDouble() ?? 0;
    if (km <= 0) {
      for (final k in ['radiusKm', 'radiusShopId', 'radiusLat', 'radiusLng']) {
        data.remove(k);
      }
      return;
    }
    if (!radiusOptionsKm.contains(km.round())) throw StateError('Choose a radius from the list: 5, 10, 25, 50 or 100 km.');
    final shop = widget.store.entries('shops').where((s) => s.id == data['radiusShopId']).firstOrNull;
    if (shop == null) throw StateError('Choose the shop whose location is the centre of the radius.');
    final lat = shop.number('latitude'), lng = shop.number('longitude');
    if (lat == 0 && lng == 0) throw StateError('"${shop.text('name')}" has no saved location yet. Add the shop location first.');
    data['radiusLat'] = lat;
    data['radiusLng'] = lng;
    final id = widget.entry?.id ?? '';
    final same = data['placement']?.toString() ?? '';
    final others = [
      for (final p in widget.store.entries('promotions')) if (p.id != id && p.text('placement') == same) p,
      if (same == 'ad') ...widget.store.entries('ads'),
    ];
    final problem = areaFullMessage(Entry(id, data), others, AdsConfig.from(widget.store.entries('settings')).maxPerArea);
    if (problem != null) throw StateError(problem);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() => busy = true);
    try {
      final data = <String, dynamic>{...?widget.entry?.data, 'active': active};
      for (final field in controllers.entries) {
        final value = field.value.text.trim();
        if (numeric.contains(field.key)) {
          data[field.key] = num.tryParse(value) ?? 0;
        } else if (field.key == 'prices') {
          data[field.key] = <String, num>{};
          for (final line
              in value.split('\n').where((l) => l.trim().isNotEmpty)) {
            final parts = line.split('=');
            if (parts.length != 2 ||
                !RegExp(r'^\d{6}$').hasMatch(parts[0].trim()) ||
                num.tryParse(parts[1]) == null ||
                num.parse(parts[1]) < 0) {
              throw StateError('Use pincode=price, for example 560001=249.');
            }
            (data[field.key] as Map)[parts[0].trim()] = num.parse(parts[1]);
          }
        } else if (field.key == 'translations') {
          data[field.key] = <String, String>{};
          for (final line
              in value.split('\n').where((l) => l.trim().isNotEmpty)) {
            final separator = line.indexOf('=');
            if (separator < 2) {
              throw StateError('Use language=text, for example hi=नमस्ते.');
            }
            (data[field.key] as Map)[line.substring(0, separator).trim()] = line
                .substring(separator + 1)
                .trim();
          }
        } else if (field.key == 'images') {
          data[field.key] = value
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList();
        } else if (field.key == 'geoTargetArea') {
          // Not a real Firestore field — handled below via pickedShape.
        } else {
          data[field.key] = value;
        }
      }
      if (widget.collection == 'promotions') _applyRadius(data);
      // A record of the services collection is a service listing unless it is one of the fixed service types.
      if (widget.collection == 'services' && data['kind'] == null) data['kind'] = 'service';
      if (pickedShape != null) {
        data['geoShape'] = pickedShape;
        if (pickedShape == 'rectangle' && pickedRectangle != null) {
          data['targetRectangle'] = pickedRectangle;
        } else {
          data.remove('targetRectangle');
        }
        if (pickedShape == 'polygon' && pickedPolygon != null) {
          data['targetPolygon'] = pickedPolygon;
        } else {
          data.remove('targetPolygon');
        }
      }
      final start = DateTime.tryParse(data['startsAt']?.toString() ?? '');
      final end = DateTime.tryParse(data['endsAt']?.toString() ?? '');
      if (start != null && end != null && !end.isAfter(start)) {
        throw StateError('End time must be after start time.');
      }
      if (start != null) {
        data['startsAt'] = start.toUtc().toIso8601String();
      }
      if (end != null) {
        data['endsAt'] = end.toUtc().toIso8601String();
      }
      // The Theme record used to be saved without any name (a blank row in the old list); it now always has one.
      if (widget.collection == 'theme' && (data['name']?.toString() ?? '').isEmpty) data['name'] = 'Theme';
      final id =
          widget.entry?.id ??
          (widget.collection == 'settings'
              ? 'business'
              : widget.collection == 'scrollingText'
              ? 'scrollingText'
              : widget.collection == 'theme'
              ? 'theme'
              : '${widget.collection.substring(0, 1)}${DateTime.now().microsecondsSinceEpoch}');
      final collection =
          widget.collection == 'scrollingText' || widget.collection == 'theme'
          ? 'settings'
          : widget.collection;
      final original = widget.entry?.data;
      if (original == null) {
        await widget.store.save(collection, Entry(id, data));
      } else {
        // Editing: write only what this form actually changed, so stock/ratings
        // changed by orders or reviews while the form was open are not overwritten.
        await widget.store.updateFields(
          collection,
          id,
          {
            for (final e in data.entries)
              if (!sameFieldValue(e.value, original[e.key])) e.key: e.value,
          },
          remove: {
            for (final key in original.keys)
              if (!data.containsKey(key)) key,
          },
          fallback: Entry(id, data),
        );
      }
      if (mounted) {
        if (!widget.embedded) Navigator.pop(context);
        message(context, 'Saved successfully');
      }
    } catch (e) {
      if (mounted) {
        message(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void preview() {
    final title = controllers['section']?.text.trim().isNotEmpty == true
        ? controllers['section']!.text.trim()
        : widget.collection;
    final sample = controllers['name']?.text.trim().isNotEmpty == true
        ? controllers['name']!.text.trim()
        : 'Preview';
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('$title preview'),
        content: Container(
          // A phone-width dialog has less than 420px available once the default AlertDialog
          // inset padding is subtracted; never request more than actually fits.
          width: (MediaQuery.sizeOf(context).width - 80).clamp(240, 420),
          padding: EdgeInsets.all(
            double.tryParse(controllers['padding']?.text ?? '') ?? 16,
          ),
          decoration: BoxDecoration(
            color: colorFromHex(
              controllers['backgroundColor']?.text ?? '',
              Theme.of(context).colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(
              double.tryParse(controllers['radius']?.text ?? '') ?? 12,
            ),
            border: Border.all(
              color: colorFromHex(
                controllers['borderColor']?.text ?? '',
                Colors.transparent,
              ),
              width:
                  double.tryParse(controllers['borderWidth']?.text ?? '') ?? 0,
            ),
          ),
          child: Text(
            sample,
            style: sectionTextStyle(
              Entry('', {
                'textColor': controllers['textColor']?.text ?? '',
                'fontFamily': controllers['fontFamily']?.text ?? '',
                'fontSize': double.tryParse(
                  controllers['fontSize']?.text ?? '',
                ),
                'fontWeight': double.tryParse(
                  controllers['fontWeight']?.text ?? '',
                ),
                'fontStyle': controllers['fontStyle']?.text ?? '',
              }),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> resetSection() async {
    if (widget.entry == null) {
      for (final controller in controllers.values) {
        controller.clear();
      }
      return;
    }
    final id = widget.entry!.id;
    // Business Profile, Theme and Scrolling Text are single records: resetting deletes the saved record, and every value in it goes back to
    // its default (empty). That is listed first, and confirmed.
    final single = const {'settings', 'theme', 'scrollingText'}.contains(widget.collection);
    if (single) {
      final rows = [
        for (final f in fields[widget.collection]!.entries)
          if (widget.entry!.data[f.key] != null && '${widget.entry!.data[f.key]}'.trim().isNotEmpty)
            ResetRow(f.key, f.value.split(' (').first, describeValue(widget.entry!.data[f.key]), 'empty (default)'),
      ];
      final ok = await confirmReset(
        context,
        title: 'Reset ${adminSections[widget.collection] ?? widget.collection} to default?',
        intro: 'The saved ${adminSections[widget.collection] ?? widget.collection} is cleared: every value below goes back to its default.',
        rows: rows,
      );
      if (!ok || !mounted) return;
    }
    await widget.store.delete('settings', id);
    final fresh = single ? await widget.store.freshRecord('settings', id) : null;
    if (!mounted) return;
    if (single) {
      await showResetDone(
        context,
        title: fresh == null ? 'Reset complete' : 'Reset incomplete',
        rows: const [],
        warning: fresh == null ? 'The saved record was cleared and confirmed. The site uses the defaults now.' : 'The record could not be cleared. Try again.',
      );
    } else {
      message(context, 'Reset to default');
    }
    // A form shown inside Settings stays (it reopens empty); a stand-alone form closes.
    if (mounted && !widget.embedded) Navigator.pop(context);
  }

  Widget field(String key, String label) {
    if (_isColorField(key)) {
      return ColorPickerField(
        label: label,
        value: controllers[key]!.text,
        onChanged: (v) => setState(() => controllers[key]!.text = v),
      );
    }
    if (key == 'fontWeight') {
      final current = controllers[key]!.text.trim();
      return DropdownButtonFormField<String>(
        initialValue: _fontWeightOptions.containsKey(current) ? current : null,
        decoration: InputDecoration(labelText: label),
        hint: const Text('Theme default'),
        items: [
          for (final entry in _fontWeightOptions.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) => setState(() => controllers[key]!.text = v ?? ''),
      );
    }
    List<DropdownMenuItem<String>>? options;
    if (['position', 'scrollEnabled'].contains(key)) {
      options =
          (key == 'position' ? ['start', 'center', 'end'] : ['false', 'true'])
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList();
    } else if (key == 'notifySubscribers') {
      options = const [
        DropdownMenuItem(
          value: '',
          child: Text('Automatic (all offers except the ticker)'),
        ),
        DropdownMenuItem(
          value: 'true',
          child: Text('Always notify subscribers'),
        ),
        DropdownMenuItem(
          value: 'false',
          child: Text('Never notify subscribers'),
        ),
      ];
    } else if (key == 'defaultPaymentMethod') {
      options = const [
        DropdownMenuItem(
          value: 'direct_vendor',
          child: Text('Customer pays vendor directly'),
        ),
        DropdownMenuItem(
          value: 'cash_on_delivery',
          child: Text('Cash on delivery'),
        ),
        DropdownMenuItem(
          value: 'platform_collected',
          child: Text('Platform collected (future)'),
        ),
      ];
    } else if (widget.collection == 'promotions' && key == 'radiusKm') {
      options = [
        const DropdownMenuItem(value: '', child: Text('No radius (as before)')),
        for (final km in radiusOptionsKm) DropdownMenuItem(value: '$km', child: Text('$km km')),
      ];
    } else if (widget.collection == 'promotions' && key == 'radiusShopId') {
      options = [
        const DropdownMenuItem(value: '', child: Text('None')),
        for (final shop in widget.store.entries('shops'))
          if (shop.number('latitude') != 0 || shop.number('longitude') != 0) DropdownMenuItem(value: shop.id, child: Text(shop.text('name'), overflow: TextOverflow.ellipsis)),
      ];
    } else if (['categoryId', 'parentId', 'shopId'].contains(key)) {
      options = [
        const DropdownMenuItem(value: '', child: Text('None')),
        ...widget.store
            .entries(key == 'shopId' ? 'shops' : 'categories')
            .where((e) => e.id != widget.entry?.id)
            .map(
              (e) => DropdownMenuItem(value: e.id, child: Text(e.text('name'))),
            ),
      ];
    } else if (key == 'section') {
      options =
          [
                'header',
                'logo',
                'user',
                'search',
                'notice',
                'promo',
                'offers',
                'categories',
                'products',
                'boxes',
                'ads',
                'background',
              ]
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList();
    } else if (key == 'kind' ||
        key == 'placement' ||
        key == 'mode' ||
        key == 'direction' ||
        key == 'noticeType' ||
        key == 'playback') {
      options =
          (key == 'kind'
                  ? ['product']
                  : key == 'placement'
                  ? ['carousel', 'ticker', 'ad', 'box']
                  : key == 'mode'
                  ? ['light', 'dark', 'custom']
                  : key == 'noticeType'
                  ? [
                      'importantNews',
                      'importantUpdates',
                      'customerNotices',
                      'offers',
                      'deliveryInformation',
                      'serviceAnnouncements',
                      'stateSpecificNotices',
                      'generalAlerts',
                    ]
                  : key == 'playback'
                  ? ['running', 'stopped', 'paused']
                  : ['rtl', 'ltr'])
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList();
    }
    if (options != null) {
      // A DropdownButtonFormField crashes with an assertion error unless its
      // initialValue is either null or matches exactly one item's value, and
      // duplicate item values trip the same assertion. Stored data can drift
      // out of sync with this fixed options list (a blank/never-set field, an
      // old value no longer offered, or — for categoryId/parentId/shopId,
      // whose items come from live store data — a stray duplicate id), so
      // both are normalized defensively rather than trusted as already valid.
      final uniqueOptions = <String, DropdownMenuItem<String>>{
        for (final option in options) (option.value ?? ''): option,
      }.values.toList();
      var storedValue = controllers[key]?.text ?? '';
      // A radius saved as 10.0 is the list's "10".
      if (widget.collection == 'promotions' && key == 'radiusKm') storedValue = (num.tryParse(storedValue) ?? 0) > 0 ? '${num.parse(storedValue).round()}' : '';
      final initialValue = uniqueOptions.any((e) => e.value == storedValue)
          ? storedValue
          : null;
      return DropdownButtonFormField<String>(
        initialValue: initialValue,
        decoration: InputDecoration(labelText: label),
        items: uniqueOptions,
        onChanged: (v) => controllers[key]!.text = v ?? '',
        validator: (v) =>
            ['categoryId', 'shopId'].contains(key) && (v ?? '').isEmpty
            ? 'Choose a $label'
            : null,
      );
    }
    if (key == 'locations') {
      return LocationTargetField(
        controller: controllers['locations']!,
        label: label,
        quickTowns: parseServiceTowns(widget.store.business.text('serviceTowns')),
      );
    }
    if (key == 'geoTargetArea') {
      final entryData = widget.entry?.data;
      final effectiveShape =
          pickedShape ?? entryData?['geoShape']?.toString() ?? 'circle';
      final rectangle = pickedShape != null
          ? pickedRectangle
          : parseRectangleField(entryData?['targetRectangle']);
      final polygon = pickedShape != null
          ? pickedPolygon
          : parsePolygonField(entryData?['targetPolygon'])
                ?.map((p) => {'lat': p.$1, 'lng': p.$2})
                .toList();
      final lat =
          double.tryParse(controllers['targetLatitude']?.text ?? '') ?? 0;
      final lng =
          double.tryParse(controllers['targetLongitude']?.text ?? '') ?? 0;
      final radius =
          double.tryParse(controllers['targetRadiusKm']?.text ?? '') ?? 0;
      final summary = effectiveShape == 'rectangle'
          ? (rectangle == null
                ? 'No rectangle drawn yet.'
                : 'Rectangle area set.')
          : effectiveShape == 'polygon'
          ? (polygon == null
                ? 'No polygon drawn yet.'
                : 'Polygon area set (${polygon.length} points).')
          : (lat == 0 && lng == 0)
          ? 'No location targeting yet (shows everywhere, or by pincode).'
          : 'Circle: ${(radius > 0 ? radius : 10).round()} km around ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}.';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(summary),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final start = DateTime.tryParse(
                controllers['startsAt']?.text ?? '',
              );
              final end = DateTime.tryParse(controllers['endsAt']?.text ?? '');
              final result = await Navigator.push<GeoTargetResult>(
                context,
                MaterialPageRoute(
                  builder: (_) => GeoTargetPicker(
                    promotions: widget.store.entries('promotions'),
                    excludeId: widget.entry?.id,
                    windowStart: start,
                    windowEnd: end,
                    initialShape: effectiveShape,
                    initialLatitude: lat,
                    initialLongitude: lng,
                    initialRadiusKm: radius,
                    initialRectangle: rectangle,
                    initialPolygon: polygon
                        ?.map((p) => (p['lat']!, p['lng']!))
                        .toList(),
                  ),
                ),
              );
              if (result == null || !mounted) return;
              setState(() {
                pickedShape = result.shape;
                pickedRectangle = result.rectangle;
                pickedPolygon = result.polygon;
                if (result.shape == 'circle') {
                  controllers['targetLatitude']!.text = result.latitude
                      .toString();
                  controllers['targetLongitude']!.text = result.longitude
                      .toString();
                  controllers['targetRadiusKm']!.text = result.radiusKm
                      .toString();
                } else {
                  controllers['targetLatitude']!.text = '0';
                  controllers['targetLongitude']!.text = '0';
                  controllers['targetRadiusKm']!.text = '0';
                }
              });
            },
            icon: const Icon(Icons.map_outlined),
            label: const Text('Choose area on map'),
          ),
        ],
      );
    }
    return TextFormField(
      controller: controllers[key],
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: ['startsAt', 'endsAt'].contains(key)
            ? IconButton(
                tooltip: 'Choose date and time',
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.tryParse(controllers[key]!.text) ??
                        DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (date == null || !mounted) {
                    return;
                  }
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time != null && mounted) {
                    setState(
                      () => controllers[key]!.text = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      ).toIso8601String(),
                    );
                  }
                },
              )
            : null,
      ),
      minLines:
          ['description', 'headerContact', 'prices', 'images', 'translations'].contains(key)
          ? 3
          : 1,
      maxLines:
          ['description', 'headerContact', 'prices', 'images', 'translations'].contains(key)
          ? 5
          : 1,
      keyboardType: numeric.contains(key)
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      validator: (raw) {
        final v = raw?.trim() ?? '';
        if (key == 'name' && v.isEmpty) {
          return 'Enter a name';
        }
        if (numeric.contains(key)) {
          // Blank is valid for every numeric field except coordinates: the
          // form's own save() already defaults a blank value to zero, and for
          // most of these fields (compareAtPrice, deliveryFee, stopAfter...)
          // zero/blank is the documented "off"/"automatic" state. Latitude
          // and longitude have no such default — 0,0 is a real, wrong place.
          // A product or service must have a real price: a blank or 0 price would
          // put a free item on sale.
          if (key == 'price' && widget.collection == 'products') {
            final price = num.tryParse(v);
            if (price == null || !price.isFinite || price <= 0) {
              return 'Enter a price above 0';
            }
          }
          if (v.isEmpty && !['latitude', 'longitude'].contains(key)) {
            return null;
          }
          final n = num.tryParse(v);
          if (n == null || !n.isFinite) {
            return 'Enter a valid number';
          }
          if (![
                'latitude',
                'longitude',
                'targetLatitude',
                'targetLongitude',
              ].contains(key) &&
              n < 0) {
            return 'Use zero or more';
          }
          if (key == 'latitude' && n.abs() > 90 ||
              key == 'longitude' && n.abs() > 180) {
            return 'Outside coordinate range';
          }
          if (key == 'targetLatitude' && n.abs() > 90 ||
              key == 'targetLongitude' && n.abs() > 180) {
            return 'Outside coordinate range';
          }
          if (key == 'stock' && n != n.round()) {
            return 'Use a whole number';
          }
          if (['vendorPhotoLimit', 'fieldPhotoLimit'].contains(key) &&
              v.isNotEmpty &&
              (n < 1 || n > 9)) {
            return 'Enter a number from 1 to 9';
          }
          if (['quickItemsPerDayStaff', 'quickItemsPerDayVendor'].contains(key) &&
              v.isNotEmpty &&
              (n < 1 || n > 1000 || n != n.round())) {
            return 'Enter a whole number from 1 to 1000';
          }
        }
        if (['startsAt', 'endsAt'].contains(key) &&
            v.isNotEmpty &&
            DateTime.tryParse(v) == null) {
          return 'Use YYYY-MM-DDTHH:MM:SS, optionally with a timezone';
        }
        if (key == 'pincode' && !RegExp(r'^\d{6}$').hasMatch(v)) {
          return 'Enter six digits';
        }
        if (key == 'targetPincode' &&
            v.isNotEmpty &&
            !RegExp(r'^\d{6}$').hasMatch(v)) {
          return 'Enter six digits';
        }
        if (key == 'imageUrl' &&
            v.isNotEmpty &&
            Uri.tryParse(v)?.scheme != 'https') {
          return 'Use an HTTPS image URL';
        }
        if (key == 'websiteUrl' &&
            v.isNotEmpty &&
            Uri.tryParse(v)?.scheme != 'https') {
          return 'Use an HTTPS website URL';
        }
        if (key == 'vendorSignupUrl' &&
            v.isNotEmpty &&
            Uri.tryParse(v)?.scheme != 'https') {
          return 'Use an HTTPS vendor signup URL';
        }
        if (key == 'supportEmail' &&
            v.isNotEmpty &&
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
          return 'Enter a valid email address';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _formBody();
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.entry == null
              ? 'Add ${widget.collection}'
              : 'Edit ${widget.entry!.text('name', adminSections[widget.collection] ?? widget.collection)}',
        ),
      ),
      body: body,
    );
  }

  Widget _formBody() => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Make it yours',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Update the details below. Hide an item any time without deleting it.',
              ),
              const SizedBox(height: 24),
              for (final f in fields[widget.collection]!.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: field(f.key, f.value),
                ),
              if (controllers.containsKey('imageUrl'))
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          try {
                            final file = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                            );
                            if (file == null) {
                              return;
                            }
                            setState(() => busy = true);
                            final url = await widget.store.upload(file);
                            if (mounted) {
                              setState(
                                () => controllers['imageUrl']!.text = url,
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              message(context, e);
                            }
                          } finally {
                            if (mounted) {
                              setState(() => busy = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.upload),
                  label: Text(widget.collection == 'settings' ? 'Upload logo (JPG or PNG)' : 'Upload image'),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : preview,
                      icon: const Icon(Icons.preview_outlined),
                      label: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : resetSection,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset to default'),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                value: active,
                onChanged: (v) => setState(() => active = v),
                title: const Text('Published'),
                subtitle: const Text(
                  'Turn off to hide this item from customers.',
                ),
              ),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
}
