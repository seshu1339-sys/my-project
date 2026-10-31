import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/places.dart';
import '../domain/quick_items.dart';
import '../services/location.dart';
import '../services/places_directory.dart';

// ---------------------------------------------------------------------------------------------
// Quick Add Item for Staff and Vendors, on a phone: big buttons. The server
// (functions/quick-items.js) enforces everything; these screens only make it easy.
//   Staff  : one item at a time; the town + pincode are found from the phone's GPS (and can be changed).
//   Vendor : the shop location is taken once by GPS at the shop and then locked; up to 5 items with
//            photos at once, only while standing within 100 m of the shop.
// ---------------------------------------------------------------------------------------------

/// A vendor may add items only within this many metres of their locked shop (the server checks too).
const quickShopRadiusMetres = 100.0;
const quickMaxBatch = 5;
const quickNotAtShop = 'మీరు మీ షాప్ దగ్గర లేరు (You are not near your shop).';

class QuickFix {
  const QuickFix(this.latitude, this.longitude);
  final double latitude, longitude;
}

/// A place an item is for: a town of the pincode directory, or an extra place the admin added.
class QuickPlace {
  const QuickPlace({required this.town, this.district = '', this.pincode = '', this.state = '', this.locationId = ''});
  final String town, district, pincode, state, locationId;

  factory QuickPlace.fromPlace(Place place) =>
      QuickPlace(town: place.town, district: place.district, pincode: place.pincode, state: place.state);
  factory QuickPlace.fromEntry(Entry location) => QuickPlace(
    town: location.text('town', location.text('name', location.id)),
    district: location.text('district'),
    pincode: location.text('pincode'),
    locationId: location.id,
  );
  factory QuickPlace.fromItem(Entry item) => QuickPlace(
    town: item.text('locationTown', item.text('locationName')),
    district: item.text('locationDistrict'),
    pincode: item.text('locationPincode'),
    state: item.text('locationState'),
    locationId: item.text('locationId'),
  );

  String get label => [town, if (district.isNotEmpty) district].join(', ');
  String get key => locationId.isNotEmpty ? locationId : '$town|$district|$pincode';

  /// What the server expects for this place.
  Map<String, Object?> toPayload() => locationId.isNotEmpty
      ? {'locationId': locationId}
      : {'locationTown': town, 'locationDistrict': district, 'locationPincode': pincode};
}

typedef QuickLocate = Future<QuickFix> Function();
typedef QuickPlaceFinder = Future<Place?> Function(double latitude, double longitude);
typedef QuickPlacesLoader = Future<PlacesIndex> Function();
typedef QuickCall = Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data);
typedef QuickPhotoPicker = Future<QuickPhotoResult?> Function(ImageSource source);

class QuickPhotoResult {
  const QuickPhotoResult(this.submissionId, this.bytes);
  final String submissionId;
  final Uint8List bytes;
}

/// The phone's camera, GPS, the pincode directory and the server -- each replaceable in tests.
class QuickEnv {
  const QuickEnv({this.locate, this.findPlace, this.loadPlaces, this.call, this.pick});
  final QuickLocate? locate;
  final QuickPlaceFinder? findPlace;
  final QuickPlacesLoader? loadPlaces;
  final QuickCall? call;
  final QuickPhotoPicker? pick;

  Future<QuickFix> fix() async {
    if (locate != null) return locate!();
    final position = await currentPosition(action: 'find where you are');
    return QuickFix(position.latitude, position.longitude);
  }

  /// The town nearest to a GPS fix, from the pincode directory.
  Future<Place?> place(double latitude, double longitude) async {
    if (findPlace != null) return findPlace!(latitude, longitude);
    return (await PlacesDirectory.instance.loadForPoint(latitude, longitude)).nearestTown(latitude, longitude);
  }

  /// The directory for the search box: the state(s) already loaded for the GPS fix, else all of India.
  Future<PlacesIndex> places() async =>
      loadPlaces != null ? loadPlaces!() : (PlacesDirectory.instance.ready ?? await PlacesDirectory.instance.loadAll());
  Future<Map<String, dynamic>> run(Store store, String name, Map<String, dynamic> data) => (call ?? store.call)(name, data);
}

String quickCleanError(Object e) => '$e'.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '').replaceFirst('Bad state: ', '');

/// How far (in metres) a GPS fix is from the vendor's locked shop; null when the shop has no location yet.
double? quickMetresFromShop(Entry account, QuickFix fix) {
  final lat = account.data['shopLatitude'], lng = account.data['shopLongitude'];
  if (lat is! num || lng is! num) return null;
  return distanceKmBetween(fix.latitude, fix.longitude, lat.toDouble(), lng.toDouble()) * 1000;
}

/// What the form sends: the same fields the saveQuickItem function checks.
List<String> quickItemErrors({
  required String name,
  required String rate,
  required String? unit,
  required bool hasPhoto,
  required bool needsLocation,
  required String? locationId,
  required QuickTiming timing,
  DateTime? now,
}) {
  final price = double.tryParse(rate.trim());
  return [
    if (!hasPhoto) 'Take or choose a photo of the item.',
    if (name.trim().length < 2) 'Enter the item name.',
    if (price == null || price <= 0) 'Enter the rate above 0.',
    if (unit == null) 'Choose the unit, such as per kg or per piece.',
    if (needsLocation && (locationId == null || locationId.isEmpty)) 'Choose the location.',
    ...quickTimingErrors(timing, now),
  ];
}

List<String> quickTimingErrors(QuickTiming timing, DateTime? now) => [
  if (timing.startMode == 'schedule' && timing.scheduleAt == null) 'Pick the date and time to start.',
  if (timing.startMode == 'schedule' &&
      timing.scheduleAt != null &&
      timing.scheduleAt!.isBefore((now ?? DateTime.now()).subtract(const Duration(minutes: 5))))
    'The start time must be in the future.',
];

/// When an item should start and how long it shows.
class QuickTiming {
  QuickTiming({
    this.startMode = 'now',
    this.scheduleAt,
    this.durationUnit = 'hours',
    this.durationValue = 2,
  });
  String startMode;
  DateTime? scheduleAt;
  String durationUnit;
  int durationValue;

  Map<String, Object?> toPayload() => {
    'startMode': startMode,
    if (startMode == 'schedule' && scheduleAt != null) 'scheduleAt': scheduleAt!.millisecondsSinceEpoch,
    'durationUnit': durationUnit,
    'durationValue': durationValue,
  };
}

String quickDateTimeLabel(DateTime time) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '${time.day} ${months[time.month - 1]}, $hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

/// "Start: Now / Schedule" and "Show for: Hours 1-4 / Days 1-3" -- shared by the forms and the
/// re-activate dialog.
class QuickTimingFields extends StatefulWidget {
  const QuickTimingFields({super.key, required this.timing, this.onChanged});
  final QuickTiming timing;
  final VoidCallback? onChanged;
  @override
  State<QuickTimingFields> createState() => _QuickTimingFieldsState();
}

class _QuickTimingFieldsState extends State<QuickTimingFields> {
  QuickTiming get t => widget.timing;
  void _changed(VoidCallback change) {
    setState(change);
    widget.onChanged?.call();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: t.scheduleAt ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(t.scheduleAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    _changed(() => t.scheduleAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final choices = t.durationUnit == 'days' ? quickDayChoices : quickHourChoices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Start', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          key: const ValueKey('quick-start-mode'),
          segments: const [
            ButtonSegment(value: 'now', label: Text('Now'), icon: Icon(Icons.bolt)),
            ButtonSegment(value: 'schedule', label: Text('Schedule'), icon: Icon(Icons.event)),
          ],
          selected: {t.startMode},
          onSelectionChanged: (s) => _changed(() => t.startMode = s.first),
        ),
        if (t.startMode == 'schedule') ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              key: const ValueKey('quick-pick-schedule'),
              onPressed: _pickSchedule,
              icon: const Icon(Icons.schedule),
              label: Text(t.scheduleAt == null ? 'Pick date and time' : quickDateTimeLabel(t.scheduleAt!)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('The item stays hidden until then.', style: TextStyle(fontSize: 12)),
          ),
        ],
        const SizedBox(height: 16),
        Text('Show for', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          key: const ValueKey('quick-duration-unit'),
          segments: const [
            ButtonSegment(value: 'hours', label: Text('Hours')),
            ButtonSegment(value: 'days', label: Text('Days')),
          ],
          selected: {t.durationUnit},
          onSelectionChanged: (s) => _changed(() {
            t.durationUnit = s.first;
            if (!(s.first == 'days' ? quickDayChoices : quickHourChoices).contains(t.durationValue)) {
              t.durationValue = 1;
            }
          }),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            for (final value in choices)
              ChoiceChip(
                key: ValueKey('quick-duration-$value'),
                label: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text(quickDurationLabel(t.durationUnit, value), style: const TextStyle(fontSize: 16)),
                ),
                selected: t.durationValue == value,
                onSelected: (_) => _changed(() => t.durationValue = value),
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('The time counts from when the item goes live, not from when you save.', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
