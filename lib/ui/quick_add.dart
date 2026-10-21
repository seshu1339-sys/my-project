import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
    return (await PlacesDirectory.instance.load()).nearestTown(latitude, longitude);
  }

  Future<PlacesIndex> places() => (loadPlaces ?? PlacesDirectory.instance.load)();
  Future<Map<String, dynamic>> run(Store store, String name, Map<String, dynamic> data) => (call ?? store.call)(name, data);
}

String _cleanError(Object e) => '$e'.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '').replaceFirst('Bad state: ', '');

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
    ..._timingErrors(timing, now),
  ];
}

List<String> _timingErrors(QuickTiming timing, DateTime? now) => [
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

/// True when [uid] has a Quick Add account (any status): the vendor and staff apps then show
/// Quick Add even if the person has no vendor application / field-staff record.
class QuickAccountGate extends StatelessWidget {
  const QuickAccountGate({super.key, required this.store, required this.role, required this.otherwise, required this.quickOnly});
  final Store store;
  final String role;
  // Shown when there is no Quick Add account of this role.
  final Widget Function() otherwise;
  // Shown to a Quick Add account that is not also a regular approved vendor / active staff.
  final Widget Function() quickOnly;
  @override
  Widget build(BuildContext context) {
    final uid = store.user?.uid;
    if (uid == null) return otherwise();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('quickAccounts').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data != null && data['role'] == role) return quickOnly();
        return otherwise();
      },
    );
  }
}

/// A Quick Add account's whole screen when it has no regular vendor/staff access.
class QuickAddOnly extends StatelessWidget {
  const QuickAddOnly({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Welcome', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Add the day’s items in a few taps. The admin approves each item before customers see it.'),
      QuickAddHome(store: store),
    ],
  );
}

/// The signed-in Staff/Vendor's Quick Add record, or the reason they cannot use it.
class QuickAddHome extends StatelessWidget {
  const QuickAddHome({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final uid = store.user?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('quickAccounts').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          // Not a Quick Add account (or still loading): show nothing, the rest of the app is unchanged.
          return const SizedBox.shrink();
        }
        return QuickAddPanel(store: store, account: Entry(uid, snapshot.data!.data()!));
      },
    );
  }
}

class QuickAddPanel extends StatelessWidget {
  const QuickAddPanel({super.key, required this.store, required this.account, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final QuickEnv env;
  bool get active => account.data['active'] == true;
  bool get isVendor => account.text('role') == 'vendor';
  bool get shopLocked => account.data['shopLocked'] == true;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.bolt, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text('Quick Add Item', style: Theme.of(context).textTheme.titleLarge)),
            Text(account.text('code'), key: const ValueKey('quick-code'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          if (!isVendor)
            const Text('Your town and pincode are found from your location when you take the photo.')
          else if (shopLocked)
            Row(children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your shop: ${account.text('locationTown')}, ${account.text('locationDistrict')} • ${account.text('locationPincode')} (locked)',
                  key: const ValueKey('quick-shop-locked'),
                ),
              ),
            ])
          else
            const Text('First set your shop location. Stand at your shop and tap the button below. It is locked for good once saved.'),
          const SizedBox(height: 12),
          if (!active)
            const Text(
              'Your account is inactive, contact admin.',
              key: ValueKey('quick-inactive'),
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
            )
          else ...[
            if (isVendor && !shopLocked)
              SizedBox(
                height: 64,
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('quick-shop-setup'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => QuickShopSetupPage(store: store, account: account, env: env)),
                  ),
                  icon: const Icon(Icons.my_location, size: 28),
                  label: const Text('Set my shop location', style: TextStyle(fontSize: 20)),
                ),
              )
            else ...[
              SizedBox(
                height: 64,
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('quick-add-button'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => QuickCategoryPage(store: store, account: account, env: env)),
                  ),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 28),
                  label: Text(isVendor ? 'Add items' : 'Add an item', style: const TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('quick-my-items-button'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => QuickMyItemsPage(store: store, account: account, env: env)),
                  ),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('My Items', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

/// Vendor, once: GPS at the shop -> the nearest town and pincode from the pincode directory -> locked.
class QuickShopSetupPage extends StatefulWidget {
  const QuickShopSetupPage({super.key, required this.store, required this.account, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final QuickEnv env;
  @override
  State<QuickShopSetupPage> createState() => _QuickShopSetupPageState();
}

class _QuickShopSetupPageState extends State<QuickShopSetupPage> {
  QuickFix? fix;
  Place? place;
  String error = '';
  bool busy = false;

  Future<void> _find() async {
    setState(() {
      busy = true;
      error = '';
      place = null;
    });
    try {
      final found = await widget.env.fix();
      final nearest = await widget.env.place(found.latitude, found.longitude);
      if (!mounted) return;
      setState(() {
        fix = found;
        place = nearest;
        if (nearest == null) error = 'Your location is outside Andhra Pradesh and Telangana, so a town could not be found.';
      });
    } catch (e) {
      if (mounted) setState(() => error = _cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _lock() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.env.run(widget.store, 'setQuickShopLocation', {'latitude': fix!.latitude, 'longitude': fix!.longitude});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your shop location is saved and locked.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = _cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set my shop location')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Stand inside your shop and turn on GPS. We find your town and pincode from your location.', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            key: const ValueKey('quick-find-shop'),
            onPressed: busy ? null : _find,
            icon: const Icon(Icons.my_location),
            label: Text(fix == null ? 'Find my shop' : 'Find again', style: const TextStyle(fontSize: 18)),
          ),
        ),
        if (busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error, key: const ValueKey('quick-shop-error'), style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
          ),
        if (place != null) ...[
          const SizedBox(height: 16),
          Card(
            key: const ValueKey('quick-shop-found'),
            child: ListTile(
              leading: const Icon(Icons.storefront, size: 32),
              title: Text('${place!.town}, ${place!.district}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              subtitle: Text('${place!.state} • Pincode ${place!.pincode}'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Once you save this it is locked. You cannot change it yourself later; only the admin can.', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: FilledButton(
              key: const ValueKey('quick-lock-shop'),
              onPressed: busy ? null : _lock,
              child: const Text('Save and lock my shop location', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Step 1: the categories as big buttons.
class QuickCategoryPage extends StatelessWidget {
  const QuickCategoryPage({super.key, required this.store, required this.account, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final QuickEnv env;

  @override
  Widget build(BuildContext context) {
    final categories = store.visible('categories').where((c) => c.text('parentId').isEmpty).toList();
    final isVendor = account.text('role') == 'vendor';
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a category')),
      body: GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 4 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          for (final category in categories)
            FilledButton.tonal(
              key: ValueKey('quick-category-${category.id}'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => isVendor
                      ? QuickBatchFormPage(store: store, account: account, category: category, env: env)
                      : QuickItemFormPage(store: store, account: account, category: category, env: env),
                ),
              ),
              child: Text(category.text('name', category.id), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

/// Photo area with Camera / Gallery buttons -- shared by the single and the batch form.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.bytes, required this.busy, required this.onPick, this.height = 200, this.suffix = ''});
  final Uint8List? bytes;
  final bool busy;
  final void Function(ImageSource source) onPick;
  final double height;
  final String suffix;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        height: height,
        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Image.memory(bytes!, key: ValueKey('quick-photo-preview$suffix'), fit: BoxFit.cover)
            : Center(child: busy ? const CircularProgressIndicator() : const Icon(Icons.image_outlined, size: 56)),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton.icon(
              key: ValueKey('quick-camera$suffix'),
              onPressed: busy ? null : () => onPick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Camera', style: TextStyle(fontSize: 18)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              key: ValueKey('quick-gallery$suffix'),
              onPressed: busy ? null : () => onPick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery', style: TextStyle(fontSize: 18)),
            ),
          ),
        ),
      ]),
    ],
  );
}

Future<QuickPhotoResult?> _defaultPick(Store store, ImageSource source) async {
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
  if (file == null) return null;
  final id = '${DateTime.now().microsecondsSinceEpoch}';
  final bytes = await store.uploadQuickPhoto(id, file);
  return QuickPhotoResult(id, bytes);
}

/// Staff: search any town of the pincode directory (or one of the admin's extra places).
Future<QuickPlace?> showQuickPlacePicker(BuildContext context, Store store, QuickEnv env) {
  final text = TextEditingController();
  var results = <Place>[];
  return showDialog<QuickPlace>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: const Text('Choose the town'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('quick-place-search'),
                controller: text,
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search town or pincode', border: OutlineInputBorder()),
                onChanged: (value) async {
                  final index = await env.places();
                  setState(() => results = index.search(value, limit: 10));
                },
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final place in results)
                      ListTile(
                        key: ValueKey('quick-place-${place.pincode}-${place.name}'),
                        title: Text(place.label),
                        subtitle: Text(place.subtitle),
                        onTap: () => Navigator.pop(dialog, QuickPlace.fromPlace(place)),
                      ),
                    if (text.text.trim().isEmpty)
                      for (final extra in store.quickLocations)
                        ListTile(
                          key: ValueKey('quick-extra-${extra.id}'),
                          leading: const Icon(Icons.place_outlined),
                          title: Text(extra.text('name', extra.id)),
                          onTap: () => Navigator.pop(dialog, QuickPlace.fromEntry(extra)),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel'))],
      ),
    ),
  );
}

/// Staff (and editing): photo, name, rate + unit, the town, start, duration -- then Save.
class QuickItemFormPage extends StatefulWidget {
  const QuickItemFormPage({
    super.key,
    required this.store,
    required this.account,
    required this.category,
    this.editing,
    this.env = const QuickEnv(),
  });
  final Store store;
  final Entry account;
  final Entry category;
  final Entry? editing;
  final QuickEnv env;
  @override
  State<QuickItemFormPage> createState() => _QuickItemFormPageState();
}

class _QuickItemFormPageState extends State<QuickItemFormPage> {
  Store get store => widget.store;
  bool get isVendor => widget.account.text('role') == 'vendor';
  final name = TextEditingController();
  final rate = TextEditingController();
  String? unit;
  QuickPlace? place;
  QuickFix? lastFix;
  bool placeByHand = false, findingPlace = false;
  Uint8List? photo;
  String? submissionId;
  final timing = QuickTiming();
  List<String> errors = const [];
  bool busy = false, pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      name.text = e.text('name');
      rate.text = e.number('price').toString().replaceAll(RegExp(r'\.0$'), '');
      unit = e.text('unit');
      if (!isVendor) place = QuickPlace.fromItem(e);
      timing
        ..durationUnit = e.text('durationUnit', 'hours')
        ..durationValue = e.number('durationValue', 2).round();
    }
  }

  @override
  void dispose() {
    name.dispose();
    rate.dispose();
    super.dispose();
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  /// Staff: the phone's GPS -> the nearest town + pincode, unless they already chose one by hand.
  Future<void> _detectPlace() async {
    if (isVendor || placeByHand) return;
    setState(() => findingPlace = true);
    try {
      final fix = await widget.env.fix();
      final nearest = await widget.env.place(fix.latitude, fix.longitude);
      if (!mounted) return;
      setState(() {
        lastFix = fix;
        if (nearest != null && !placeByHand) place = QuickPlace.fromPlace(nearest);
      });
    } catch (_) {
      /* No GPS: they can choose the town themselves. */
    } finally {
      if (mounted) setState(() => findingPlace = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => pickingPhoto = true);
    try {
      final result = await (widget.env.pick ?? (s) => _defaultPick(store, s))(source);
      if (result != null && mounted) {
        setState(() {
          photo = result.bytes;
          submissionId = result.submissionId;
          errors = const [];
        });
        // The photo is taken where the item is: that is where the town is read from.
        unawaited(_detectPlace());
      }
    } catch (e) {
      if (mounted) toast(_cleanError(e));
    } finally {
      if (mounted) setState(() => pickingPhoto = false);
    }
  }

  Future<void> _changePlace() async {
    final chosen = await showQuickPlacePicker(context, store, widget.env);
    if (chosen != null && mounted) {
      setState(() {
        place = chosen;
        placeByHand = true;
      });
    }
  }

  Future<void> save() async {
    final problems = quickItemErrors(
      name: name.text,
      rate: rate.text,
      unit: unit,
      hasPhoto: photo != null || widget.editing != null,
      needsLocation: !isVendor,
      locationId: place?.key,
      timing: timing,
    );
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      QuickFix? fix = lastFix;
      if (isVendor) {
        // A vendor must be at the shop every time (the server checks again).
        fix = await widget.env.fix();
        final metres = quickMetresFromShop(widget.account, fix);
        if (metres == null || metres > quickShopRadiusMetres) {
          if (mounted) setState(() => errors = [quickNotAtShop]);
          return;
        }
      }
      await widget.env.run(store, 'saveQuickItem', {
        if (widget.editing != null) 'itemId': widget.editing!.id,
        if (submissionId != null) 'submissionId': submissionId,
        'name': name.text.trim(),
        'categoryId': widget.category.id,
        'price': double.parse(rate.text.trim()),
        'unit': unit,
        if (!isVendor) ...place!.toPayload(),
        if (fix != null) 'latitude': fix.latitude,
        if (fix != null) 'longitude': fix.longitude,
        ...timing.toPayload(),
      });
      if (!mounted) return;
      setState(() => busy = false);
      if (widget.editing != null) {
        toast('Saved. The admin will review it again.');
        Navigator.pop(context);
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Saved'),
          content: const Text('Your item was sent to the admin. It goes live after the admin approves it.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialog);
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text('Done'),
            ),
            FilledButton(
              key: const ValueKey('quick-add-next'),
              onPressed: () {
                Navigator.pop(dialog);
                Navigator.pop(context); // back to the categories for the next item
              },
              child: const Text('Add next item'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        final message = _cleanError(e);
        setState(() => errors = [message]);
        toast(message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.category.text('name', 'New item'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PhotoPicker(bytes: photo, busy: pickingPhoto, onPick: _pickPhoto),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('quick-name'),
          controller: name,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(labelText: 'Item name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 2,
            child: TextField(
              key: const ValueKey('quick-rate'),
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(labelText: 'Rate (₹)', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              key: const ValueKey('quick-unit'),
              initialValue: unit != null && quickUnits.contains(unit) ? unit : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
              items: [for (final u in quickUnits) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (v) => setState(() => unit = v),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // ---- the town: staff get it from GPS (and can change it); a vendor's is the locked shop
        if (isVendor)
          ListTile(
            key: const ValueKey('quick-location-fixed'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text('${widget.account.text('locationTown')}, ${widget.account.text('locationDistrict')}'),
            subtitle: const Text('Your shop location is locked. You must be at your shop to save.'),
          )
        else
          Card(
            key: const ValueKey('quick-place'),
            child: ListTile(
              leading: findingPlace ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.place_outlined),
              title: Text(place == null ? (findingPlace ? 'Finding your town…' : 'Town not found yet') : place!.label, key: const ValueKey('quick-place-label')),
              subtitle: Text(place == null ? 'Take the photo where the item is, or choose the town.' : [if (place!.pincode.isNotEmpty) 'Pincode ${place!.pincode}', if (!placeByHand) 'from your location'].join(' • ')),
              trailing: TextButton(key: const ValueKey('quick-place-change'), onPressed: _changePlace, child: Text(place == null ? 'Choose' : 'Change')),
            ),
          ),
        const SizedBox(height: 16),
        QuickTimingFields(timing: timing),
        const SizedBox(height: 16),
        if (errors.isNotEmpty)
          Card(
            key: const ValueKey('quick-error'),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final e in errors) Text(e.startsWith('మీరు') ? e : '• $e')],
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: FilledButton(
            key: const ValueKey('quick-save'),
            onPressed: busy ? null : save,
            child: busy ? const CircularProgressIndicator() : const Text('Save', style: TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

class _BatchRow {
  final name = TextEditingController();
  final rate = TextEditingController();
  String? unit;
  Uint8List? photo;
  String? submissionId;
  bool picking = false;
  void dispose() {
    name.dispose();
    rate.dispose();
  }
}

/// Vendor: up to 5 items with photos at once, in one category, with one start and duration. The
/// phone's GPS is checked once: the vendor must be within 100 m of the shop.
class QuickBatchFormPage extends StatefulWidget {
  const QuickBatchFormPage({super.key, required this.store, required this.account, required this.category, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final Entry category;
  final QuickEnv env;
  @override
  State<QuickBatchFormPage> createState() => _QuickBatchFormPageState();
}

class _QuickBatchFormPageState extends State<QuickBatchFormPage> {
  final rows = <_BatchRow>[_BatchRow()];
  final timing = QuickTiming();
  List<String> errors = const [];
  bool busy = false;

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> _pick(_BatchRow row, ImageSource source) async {
    setState(() => row.picking = true);
    try {
      final result = await (widget.env.pick ?? (s) => _defaultPick(widget.store, s))(source);
      if (result != null && mounted) {
        setState(() {
          row.photo = result.bytes;
          row.submissionId = result.submissionId;
          errors = const [];
        });
      }
    } catch (e) {
      if (mounted) toast(_cleanError(e));
    } finally {
      if (mounted) setState(() => row.picking = false);
    }
  }

  List<String> _errors() {
    final out = <String>[];
    for (final (i, row) in rows.indexed) {
      for (final problem in quickItemErrors(
        name: row.name.text,
        rate: row.rate.text,
        unit: row.unit,
        hasPhoto: row.photo != null,
        needsLocation: false,
        locationId: null,
        timing: QuickTiming(),
      )) {
        out.add('Item ${i + 1}: $problem');
      }
    }
    return [...out, ..._timingErrors(timing, null)];
  }

  Future<void> save() async {
    final problems = _errors();
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      final fix = await widget.env.fix();
      final metres = quickMetresFromShop(widget.account, fix);
      if (metres == null || metres > quickShopRadiusMetres) {
        if (mounted) setState(() => errors = [quickNotAtShop]);
        return;
      }
      await widget.env.run(widget.store, 'saveQuickItems', {
        'categoryId': widget.category.id,
        'items': [
          for (final row in rows)
            {
              'submissionId': row.submissionId,
              'name': row.name.text.trim(),
              'price': double.parse(row.rate.text.trim()),
              'unit': row.unit,
            },
        ],
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        ...timing.toPayload(),
      });
      if (!mounted) return;
      setState(() => busy = false);
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Saved'),
          content: Text('${rows.length} ${rows.length == 1 ? 'item was' : 'items were'} sent to the admin. They go live after the admin approves them.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialog);
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text('Done'),
            ),
            FilledButton(
              key: const ValueKey('quick-add-next'),
              onPressed: () {
                Navigator.pop(dialog);
                Navigator.pop(context);
              },
              child: const Text('Add more items'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        final message = _cleanError(e);
        setState(() => errors = [message]);
        toast(message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.category.text('name', 'Add items'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          key: const ValueKey('quick-location-fixed'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: Text('${widget.account.text('locationTown')}, ${widget.account.text('locationDistrict')}'),
          subtitle: const Text('Your shop. You must be within 100 m of it to save.'),
        ),
        for (final (i, row) in rows.indexed)
          Card(
            key: ValueKey('quick-row-$i'),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: Text('Item ${i + 1}', style: Theme.of(context).textTheme.titleMedium)),
                    if (rows.length > 1)
                      IconButton(
                        key: ValueKey('quick-row-remove-$i'),
                        tooltip: 'Remove this item',
                        onPressed: () => setState(() => rows.removeAt(i).dispose()),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ]),
                  _PhotoPicker(bytes: row.photo, busy: row.picking, height: 140, suffix: '-$i', onPick: (s) => _pick(row, s)),
                  const SizedBox(height: 12),
                  TextField(
                    key: ValueKey('quick-name-$i'),
                    controller: row.name,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(labelText: 'Item name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        key: ValueKey('quick-rate-$i'),
                        controller: row.rate,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(labelText: 'Rate (₹)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('quick-unit-$i'),
                        initialValue: row.unit,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                        items: [for (final u in quickUnits) DropdownMenuItem(value: u, child: Text(u))],
                        onChanged: (v) => setState(() => row.unit = v),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        if (rows.length < quickMaxBatch)
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              key: const ValueKey('quick-row-add'),
              onPressed: () => setState(() => rows.add(_BatchRow())),
              icon: const Icon(Icons.add),
              label: Text('Add another item (${rows.length}/$quickMaxBatch)'),
            ),
          ),
        const SizedBox(height: 16),
        QuickTimingFields(timing: timing),
        const SizedBox(height: 16),
        if (errors.isNotEmpty)
          Card(
            key: const ValueKey('quick-error'),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final e in errors) Text(e.startsWith('మీరు') ? e : '• $e')],
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: FilledButton(
            key: const ValueKey('quick-save'),
            onPressed: busy ? null : save,
            child: busy ? const CircularProgressIndicator() : Text('Save ${rows.length} ${rows.length == 1 ? 'item' : 'items'}', style: const TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

/// "My Items": Scheduled / Live / Expired, with Edit, Cancel and Re-activate.
class QuickMyItemsPage extends StatelessWidget {
  const QuickMyItemsPage({super.key, required this.store, required this.account, this.stream, this.env = const QuickEnv()});
  final Store store;
  final Entry account;
  final QuickEnv env;
  // Test seam.
  final Stream<List<Entry>>? stream;

  Stream<List<Entry>> _items() =>
      stream ??
      store.firestore.collection('quickItems').where('ownerUid', isEqualTo: account.id).snapshots().map(
        (s) => s.docs.map((d) => Entry(d.id, d.data())).toList(),
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('My Items'),
        bottom: const TabBar(tabs: [Tab(text: 'Scheduled'), Tab(text: 'Live'), Tab(text: 'Expired')]),
      ),
      body: StreamBuilder<List<Entry>>(
        stream: _items(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Items could not load.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return QuickItemTabs(items: snapshot.data!, store: store, account: account, env: env);
        },
      ),
    ),
  );
}

/// The three lists, re-evaluated every 30 seconds so an item moves from Scheduled to Live to
/// Expired on its own.
class QuickItemTabs extends StatefulWidget {
  const QuickItemTabs({super.key, required this.items, required this.store, required this.account, this.env = const QuickEnv(), this.now});
  final List<Entry> items;
  final Store store;
  final Entry account;
  final QuickEnv env;
  final DateTime Function()? now;
  @override
  State<QuickItemTabs> createState() => _QuickItemTabsState();
}

class _QuickItemTabsState extends State<QuickItemTabs> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime get now => (widget.now ?? DateTime.now)();
  bool get isVendor => widget.account.text('role') == 'vendor';

  void _say(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String function, Map<String, dynamic> data, String done) async {
    try {
      await widget.env.run(widget.store, function, data);
      _say(done);
    } catch (e) {
      _say(_cleanError(e));
    }
  }

  Future<void> _reactivate(Entry item) async {
    final timing = QuickTiming(durationUnit: item.text('durationUnit', 'hours'), durationValue: item.number('durationValue', 2).round());
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Show this item again'),
        content: SingleChildScrollView(child: QuickTimingFields(timing: timing)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Back')),
          FilledButton(key: const ValueKey('quick-reactivate-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Send to admin')),
        ],
      ),
    );
    if (ok != true) return;
    if (timing.startMode == 'schedule' && timing.scheduleAt == null) {
      _say('Pick the date and time to start.');
      return;
    }
    QuickFix? fix;
    if (isVendor) {
      try {
        fix = await widget.env.fix();
      } catch (e) {
        _say(_cleanError(e));
        return;
      }
      final metres = quickMetresFromShop(widget.account, fix);
      if (metres == null || metres > quickShopRadiusMetres) {
        _say(quickNotAtShop);
        return;
      }
    }
    await _run(
      'reactivateQuickItem',
      {'itemId': item.id, ...timing.toPayload(), if (fix != null) 'latitude': fix.latitude, if (fix != null) 'longitude': fix.longitude},
      'Sent to the admin for approval.',
    );
  }

  void _edit(Entry item) {
    final category = widget.store.entries('categories').where((c) => c.id == item.text('categoryId')).firstOrNull ??
        Entry(item.text('categoryId'), {'name': item.text('categoryName')});
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuickItemFormPage(store: widget.store, account: widget.account, category: category, editing: item, env: widget.env),
      ),
    );
  }

  String _status(Entry item, QuickPhase phase) {
    switch (phase) {
      case QuickPhase.pending:
        return 'Waiting for admin approval';
      case QuickPhase.scheduled:
        return 'Starts ${quickDateTimeLabel(quickStartsAt(item)!)}';
      case QuickPhase.live:
        return 'Available for ${quickCountdown(quickExpiresAt(item)!.difference(now))}';
      case QuickPhase.expired:
        return 'Ended ${quickDateTimeLabel(quickExpiresAt(item) ?? now)}';
      case QuickPhase.rejected:
        final reason = item.text('decisionReason');
        return 'Rejected${reason.isEmpty ? '' : ': $reason'}';
      case QuickPhase.cancelled:
        return 'Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final byTab = {for (final tab in QuickTab.values) tab: <Entry>[]};
    for (final item in widget.items) {
      byTab[quickTabOf(quickPhase(item, now))]!.add(item);
    }
    for (final list in byTab.values) {
      list.sort((a, b) => b.id.compareTo(a.id));
    }
    return TabBarView(
      children: [
        for (final tab in QuickTab.values)
          byTab[tab]!.isEmpty
              ? Center(key: ValueKey('quick-empty-${tab.name}'), child: Text('No ${tab.name} items.'))
              : ListView(
                  key: ValueKey('quick-list-${tab.name}'),
                  padding: const EdgeInsets.all(12),
                  children: [for (final item in byTab[tab]!) _tile(item)],
                ),
      ],
    );
  }

  Widget _tile(Entry item) {
    final phase = quickPhase(item, now);
    final canCancel = {QuickPhase.pending, QuickPhase.scheduled, QuickPhase.live}.contains(phase);
    final canReactivate = {QuickPhase.expired, QuickPhase.cancelled, QuickPhase.rejected}.contains(phase);
    return Card(
      key: ValueKey('quick-item-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              QuickItemPhoto(store: widget.store, item: item, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.text('name'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('₹${_money(item.number('price'))} ${item.text('unit')} • ${item.text('locationName')}'),
                    Text(item.text('categoryName'), style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(_status(item, phase), key: ValueKey('quick-status-${item.id}'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                key: ValueKey('quick-edit-${item.id}'),
                onPressed: () => _edit(item),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              if (canCancel)
                OutlinedButton.icon(
                  key: ValueKey('quick-cancel-${item.id}'),
                  onPressed: () => _run('cancelQuickItem', {'itemId': item.id}, 'Cancelled.'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
              if (canReactivate)
                FilledButton.icon(
                  key: ValueKey('quick-reactivate-${item.id}'),
                  onPressed: () => _reactivate(item),
                  icon: const Icon(Icons.replay),
                  label: const Text('Re-activate'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

String _money(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

// Download links of private photos, looked up once per path.
final _storageUrls = <String, Future<String>>{};

/// The item's photo: the public one once approved, else the owner's private upload.
class QuickItemPhoto extends StatelessWidget {
  const QuickItemPhoto({super.key, required this.store, required this.item, this.size = 64});
  final Store store;
  final Entry item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = item.text('imageUrl');
    Widget box(Widget child) => ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: size, height: size, child: child));
    const placeholder = ColoredBox(color: Colors.black12, child: Icon(Icons.image_outlined));
    if (url.isNotEmpty) return box(Image.network(url, fit: BoxFit.cover, errorBuilder: (_, e, s) => placeholder));
    final path = item.text('photoPath');
    if (!store.live || path.isEmpty) return box(placeholder);
    return box(
      FutureBuilder<String>(
        future: _storageUrls.putIfAbsent(path, () => FirebaseStorage.instance.ref(path).getDownloadURL()),
        builder: (context, snapshot) => snapshot.hasData
            ? Image.network(snapshot.data!, fit: BoxFit.cover, errorBuilder: (_, e, s) => placeholder)
            : placeholder,
      ),
    );
  }
}
