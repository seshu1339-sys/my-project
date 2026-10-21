import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/quick_items.dart';

// ---------------------------------------------------------------------------------------------
// Quick Add Item for Staff and Vendors, on a phone: big buttons, one item at a time. The server
// (functions/quick-items.js) enforces everything; these screens only make it easy.
// ---------------------------------------------------------------------------------------------

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
    if (timing.startMode == 'schedule' && timing.scheduleAt == null) 'Pick the date and time to start.',
    if (timing.startMode == 'schedule' &&
        timing.scheduleAt != null &&
        timing.scheduleAt!.isBefore((now ?? DateTime.now()).subtract(const Duration(minutes: 5))))
      'The start time must be in the future.',
  ];
}

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

/// "Start: Now / Schedule" and "Show for: Hours 1-4 / Days 1-3" -- shared by the form and the
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
  const QuickAddPanel({super.key, required this.store, required this.account});
  final Store store;
  final Entry account;
  bool get active => account.data['active'] == true;
  bool get isVendor => account.text('role') == 'vendor';

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
          Text(isVendor ? 'Items are added to ${account.text('locationName')} (your shop).' : 'Add items at any location from the list.'),
          const SizedBox(height: 12),
          if (!active)
            const Text(
              'Your account is inactive, contact admin.',
              key: ValueKey('quick-inactive'),
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
            )
          else ...[
            SizedBox(
              height: 64,
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('quick-add-button'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => QuickCategoryPage(store: store, account: account)),
                ),
                icon: const Icon(Icons.add_a_photo_outlined, size: 28),
                label: const Text('Add an item', style: TextStyle(fontSize: 20)),
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
                  MaterialPageRoute<void>(builder: (_) => QuickMyItemsPage(store: store, account: account)),
                ),
                icon: const Icon(Icons.list_alt),
                label: const Text('My Items', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Step 1: the categories as big buttons.
class QuickCategoryPage extends StatelessWidget {
  const QuickCategoryPage({super.key, required this.store, required this.account, this.pick});
  final Store store;
  final Entry account;
  final QuickPhotoPicker? pick;

  @override
  Widget build(BuildContext context) {
    final categories = store.visible('categories').where((c) => c.text('parentId').isEmpty).toList();
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
                  builder: (_) => QuickItemFormPage(store: store, account: account, category: category, pick: pick),
                ),
              ),
              child: Text(category.text('name', category.id), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class QuickPhotoResult {
  const QuickPhotoResult(this.submissionId, this.bytes);
  final String submissionId;
  final Uint8List bytes;
}

typedef QuickPhotoPicker = Future<QuickPhotoResult?> Function(ImageSource source);
typedef QuickSubmit = Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

/// Step 2: photo, name, rate + unit, location, start, duration -- then Save.
class QuickItemFormPage extends StatefulWidget {
  const QuickItemFormPage({
    super.key,
    required this.store,
    required this.account,
    required this.category,
    this.editing,
    this.pick,
    this.submit,
  });
  final Store store;
  final Entry account;
  final Entry category;
  final Entry? editing;
  // Test seams: the real ones use the phone's camera/gallery, Storage and the function.
  final QuickPhotoPicker? pick;
  final QuickSubmit? submit;
  @override
  State<QuickItemFormPage> createState() => _QuickItemFormPageState();
}

class _QuickItemFormPageState extends State<QuickItemFormPage> {
  Store get store => widget.store;
  bool get isVendor => widget.account.text('role') == 'vendor';
  final name = TextEditingController();
  final rate = TextEditingController();
  String? unit;
  String? locationId;
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
      locationId = e.text('locationId');
      timing
        ..durationUnit = e.text('durationUnit', 'hours')
        ..durationValue = e.number('durationValue', 2).round();
    }
    if (isVendor) locationId = widget.account.text('locationId');
  }

  @override
  void dispose() {
    name.dispose();
    rate.dispose();
    super.dispose();
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<QuickPhotoResult?> _defaultPick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return null;
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final bytes = await store.uploadQuickPhoto(id, file);
    return QuickPhotoResult(id, bytes);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => pickingPhoto = true);
    try {
      final result = await (widget.pick ?? _defaultPick)(source);
      if (result != null && mounted) {
        setState(() {
          photo = result.bytes;
          submissionId = result.submissionId;
          errors = const [];
        });
      }
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => pickingPhoto = false);
    }
  }

  Future<Map<String, dynamic>> _defaultSubmit(Map<String, dynamic> payload) => store.call('saveQuickItem', payload);

  Future<void> save() async {
    final problems = quickItemErrors(
      name: name.text,
      rate: rate.text,
      unit: unit,
      hasPhoto: photo != null || widget.editing != null,
      needsLocation: !isVendor,
      locationId: locationId,
      timing: timing,
    );
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      await (widget.submit ?? _defaultSubmit)({
        if (widget.editing != null) 'itemId': widget.editing!.id,
        if (submissionId != null) 'submissionId': submissionId,
        'name': name.text.trim(),
        'categoryId': widget.category.id,
        'price': double.parse(rate.text.trim()),
        'unit': unit,
        if (!isVendor) 'locationId': locationId,
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
      if (mounted) toast('$e'.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locations = store.quickLocations;
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.text('name', 'New item'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- photo
          Container(
            height: 200,
            decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: photo != null
                ? Image.memory(photo!, key: const ValueKey('quick-photo-preview'), fit: BoxFit.cover)
                : Center(child: pickingPhoto ? const CircularProgressIndicator() : const Icon(Icons.image_outlined, size: 64)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  key: const ValueKey('quick-camera'),
                  onPressed: pickingPhoto ? null : () => _pickPhoto(ImageSource.camera),
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
                  key: const ValueKey('quick-gallery'),
                  onPressed: pickingPhoto ? null : () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          // ---- name, rate, unit
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
          // ---- location: staff pick from the list; a vendor's is fixed
          if (isVendor)
            ListTile(
              key: const ValueKey('quick-location-fixed'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: Text(widget.account.text('locationName', 'Your shop location')),
              subtitle: const Text('Your shop location is fixed by the admin.'),
            )
          else
            DropdownButtonFormField<String>(
              key: const ValueKey('quick-location'),
              initialValue: locations.any((l) => l.id == locationId) ? locationId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder(), prefixIcon: Icon(Icons.place_outlined)),
              items: [for (final l in locations) DropdownMenuItem(value: l.id, child: Text(l.text('name', l.id)))],
              onChanged: (v) => setState(() => locationId = v),
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
                  children: [for (final e in errors) Text('• $e')],
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
}

/// "My Items": Scheduled / Live / Expired, with Edit, Cancel and Re-activate.
class QuickMyItemsPage extends StatelessWidget {
  const QuickMyItemsPage({super.key, required this.store, required this.account, this.stream, this.call});
  final Store store;
  final Entry account;
  // Test seams.
  final Stream<List<Entry>>? stream;
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)? call;

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
          return QuickItemTabs(items: snapshot.data!, store: store, account: account, call: call);
        },
      ),
    ),
  );
}

/// The three lists, re-evaluated every 30 seconds so an item moves from Scheduled to Live to
/// Expired on its own.
class QuickItemTabs extends StatefulWidget {
  const QuickItemTabs({super.key, required this.items, required this.store, required this.account, this.call, this.now});
  final List<Entry> items;
  final Store store;
  final Entry account;
  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)? call;
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

  Future<void> _run(String function, Map<String, dynamic> data, String done) async {
    try {
      await (widget.call ?? widget.store.call)(function, data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), ''))));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick the date and time to start.')));
      return;
    }
    await _run('reactivateQuickItem', {'itemId': item.id, ...timing.toPayload()}, 'Sent to the admin for approval.');
  }

  void _edit(Entry item) {
    final category = widget.store.entries('categories').where((c) => c.id == item.text('categoryId')).firstOrNull ??
        Entry(item.text('categoryId'), {'name': item.text('categoryName')});
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QuickItemFormPage(store: widget.store, account: widget.account, category: category, editing: item),
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

// Download links of private photos, looked up once per path.
final _storageUrls = <String, Future<String>>{};

String _money(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

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
