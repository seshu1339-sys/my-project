import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/quick_items.dart';
import 'quick_add_core.dart';
import 'quick_add_photo.dart';

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
      final result = await (widget.env.pick ?? (s) => quickDefaultPick(store, s))(source);
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
      if (mounted) toast(quickCleanError(e));
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
        final message = quickCleanError(e);
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
        QuickPhotoArea(bytes: photo, busy: pickingPhoto, onPick: _pickPhoto),
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
