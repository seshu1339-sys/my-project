import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../services/location.dart';
import 'shop_map.dart';

/// Streams the signed-in staff member's own fieldStaff/{uid} doc and shows the
/// right screen for its status. Requests access once (idempotent — never
/// downgrades an already-active/suspended record) so a brand-new staff member
/// doesn't need a separate "apply" step beyond signing in.
class FieldHomePage extends StatefulWidget {
  const FieldHomePage({super.key, required this.store});
  final Store store;
  @override
  State<FieldHomePage> createState() => _FieldHomePageState();
}

class _FieldHomePageState extends State<FieldHomePage> {
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    if (store.user?.emailVerified == true) {
      store.call('requestFieldStaffAccess', const {}).catchError((_) => <String, dynamic>{});
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = store.user;
    if (user == null) return const SizedBox.shrink();
    final actions = [IconButton(tooltip: 'Log out', onPressed: store.logout, icon: const Icon(Icons.logout))];
    if (!user.emailVerified) {
      return Scaffold(
        appBar: AppBar(title: const Text('Field Assistant'), actions: actions),
        body: const _Message(
          title: 'Verify your email first',
          body: 'Sign out and use "Continue with email link" so we can verify your email. Entry submission opens once an administrator approves your access.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Field Assistant'), actions: actions),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldStaff').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _Message(title: 'Could not load your access status', body: 'Please check your connection and try again.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final status = snapshot.data!.data()?['status'];
          if (status == 'active') return FieldWorkspace(store: store, uid: user.uid);
          if (status == 'suspended') {
            return const _Message(title: 'Access suspended', body: 'Your field staff access has been suspended by the administrator. Contact them to have it reinstated.');
          }
          if (status == 'rejected') {
            return const _Message(title: 'Access request not approved', body: 'Your field staff access request was not approved. Contact the administrator for details.');
          }
          return const _Message(
            title: 'Waiting for approval',
            body: 'Your access request is waiting for administrator approval. You will be able to submit entries here once it is approved.',
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title, body;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(body, textAlign: TextAlign.center),
        ]),
      ),
    ),
  );
}

/// Shown only once the staff member's fieldStaff doc is 'active'. Lists past
/// submissions and starts a new one; the server independently re-checks
/// 'active' status for every submission regardless of what this screen shows.
class FieldWorkspace extends StatefulWidget {
  const FieldWorkspace({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<FieldWorkspace> createState() => _FieldWorkspaceState();
}

class _FieldWorkspaceState extends State<FieldWorkspace> {
  Store get store => widget.store;
  String get uid => widget.uid;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Field entries', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Capture an item at a vendor shop. Nothing you submit is visible to customers until an administrator approves it.'),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => FieldEntryForm(store: store))),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('New entry'),
      ),
      const SizedBox(height: 24),
      Text('My submissions', style: Theme.of(context).textTheme.titleLarge),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('fieldSubmissions').where('staffUid', isEqualTo: uid).limit(100).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Submissions could not load.'));
          final docs = [...snapshot.data?.docs ?? const []]..sort((a, b) {
            final ta = a.data()['submittedAt'] as Timestamp?;
            final tb = b.data()['submittedAt'] as Timestamp?;
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta);
          });
          if (docs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No submissions yet.'));
          return Column(children: [for (final doc in docs) _submissionTile(doc)]);
        },
      ),
    ],
  );

  Widget _submissionTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final item = data['item'] as Map<String, dynamic>? ?? const {};
    final shop = data['shop'] as Map<String, dynamic>?;
    final shopId = data['shopId']?.toString() ?? '';
    final shopLabel = shopId.isNotEmpty ? 'Existing shop' : (shop?['name']?.toString() ?? 'New shop');
    final status = data['status']?.toString() ?? 'pending';
    final reason = data['decisionReason']?.toString() ?? '';
    final statusText = switch (status) {
      'approved' => 'Approved',
      'rejected' => 'Rejected${reason.isEmpty ? '' : ': $reason'}',
      _ => 'Pending admin review',
    };
    return Card(child: ListTile(
      title: Text('${item['name']}'),
      subtitle: Text('₹${item['price']} • Stock ${item['stock']} • $shopLabel\n$statusText'),
      isThreeLine: true,
    ));
  }
}

/// Returns every reason a field entry must not be submitted yet. Mirrors the
/// server-side checks in functions/domain.js (fieldShopDetails/
/// fieldItemDetails) and functions/field-assistant.js's GPS requirement, the
/// same way vendorApplicationErrors() mirrors vendorApplication() — so
/// nothing incomplete is ever sent.
List<String> fieldEntryErrors({
  required bool useExistingShop,
  required bool hasExistingShop,
  required String shopName,
  required String shopAddress,
  required String shopPincode,
  required String itemName,
  required String itemPrice,
  required String itemStock,
  required bool hasPhoto,
  required bool hasLocation,
}) {
  bool between(String v, int min, int max) => v.trim().length >= min && v.trim().length <= max;
  final price = double.tryParse(itemPrice.trim());
  final stock = int.tryParse(itemStock.trim());
  return [
    if (useExistingShop && !hasExistingShop) 'Choose a shop.',
    if (!useExistingShop && !between(shopName, 2, 120)) 'Enter the shop name.',
    if (!useExistingShop && !between(shopAddress, 5, 500)) 'Enter the shop address.',
    if (!useExistingShop && !RegExp(r'^\d{6}$').hasMatch(shopPincode.trim())) 'Enter a valid six-digit pincode.',
    if (!between(itemName, 2, 120)) 'Enter the item name.',
    if (price == null || price < 0) 'Enter a valid price.',
    if (stock == null || stock < 0) 'Enter the stock quantity as a whole number.',
    if (!hasPhoto) 'Take or choose a photo of the item.',
    if (!hasLocation) "Capture the shop's GPS location.",
  ];
}

/// Capture: existing shop (searchable dropdown) or a brand-new one (name/
/// address/pincode), GPS (always captured fresh, proves the staff member was
/// actually there — required for an existing shop too), item name/price/
/// stock, and one photo. Cannot submit until every required field and the
/// photo are present; GPS auto-captures on open with a "Recapture" fallback,
/// exactly like VendorRegistrationForm.
class FieldEntryForm extends StatefulWidget {
  const FieldEntryForm({super.key, required this.store});
  final Store store;
  @override
  State<FieldEntryForm> createState() => _FieldEntryFormState();
}

class _FieldEntryFormState extends State<FieldEntryForm> {
  Store get store => widget.store;
  bool useExistingShop = true;
  String? existingShopId;
  final shopName = TextEditingController();
  final shopAddress = TextEditingController();
  final shopPincode = TextEditingController();
  final itemName = TextEditingController();
  final itemPrice = TextEditingController();
  final itemStock = TextEditingController();
  late final String submissionId = '${DateTime.now().microsecondsSinceEpoch}';
  Uint8List? photoBytes;
  bool photoReady = false;
  String? uploading;
  List<String> errors = const [];
  bool busy = false;
  Position? position;
  String? locationError;
  bool capturingLocation = true;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  Future<void> _captureLocation() async {
    setState(() {
      capturingLocation = true;
      locationError = null;
    });
    try {
      final result = await currentPosition(action: "capture the shop's location");
      if (mounted) setState(() { position = result; capturingLocation = false; });
    } catch (e) {
      if (mounted) setState(() { locationError = '$e'.replaceFirst('Bad state: ', ''); capturingLocation = false; });
    }
  }

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() => uploading = 'photo');
      final bytes = await file.readAsBytes();
      await store.uploadFieldPhoto(submissionId, file);
      if (!mounted) return;
      setState(() { photoBytes = bytes; photoReady = true; errors = const []; });
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  List<String> _errors() {
    return fieldEntryErrors(
      useExistingShop: useExistingShop,
      hasExistingShop: existingShopId != null,
      shopName: shopName.text,
      shopAddress: shopAddress.text,
      shopPincode: shopPincode.text,
      itemName: itemName.text,
      itemPrice: itemPrice.text,
      itemStock: itemStock.text,
      hasPhoto: photoReady,
      hasLocation: position != null,
    );
  }

  Future<void> submit() async {
    final problems = _errors();
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      await store.call('submitFieldEntry', {
        'shopId': useExistingShop ? existingShopId : '',
        if (!useExistingShop)
          'shop': {
            'name': shopName.text.trim(),
            'address': shopAddress.text.trim(),
            'pincode': shopPincode.text.trim(),
            'latitude': position!.latitude,
            'longitude': position!.longitude,
          },
        'item': {
          'name': itemName.text.trim(),
          'price': double.parse(itemPrice.text.trim()),
          'stock': int.parse(itemStock.text.trim()),
        },
        'submissionId': submissionId,
        'visitLatitude': position!.latitude,
        'visitLongitude': position!.longitude,
      });
      if (mounted) {
        toast('Submitted for admin review');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget get _shopSection {
    final shops = store.entries('shops').where((e) => e.active).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Shop', style: TextStyle(fontWeight: FontWeight.bold)),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Existing shop')),
          ButtonSegment(value: false, label: Text('New shop')),
        ],
        selected: {useExistingShop},
        onSelectionChanged: (selection) => setState(() => useExistingShop = selection.first),
      ),
      const SizedBox(height: 8),
      if (useExistingShop)
        DropdownButtonFormField<String>(
          initialValue: existingShopId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Choose the shop you are visiting'),
          items: [for (final s in shops) DropdownMenuItem(value: s.id, child: Text(s.text('name', s.id)))],
          onChanged: (v) => setState(() => existingShopId = v),
        )
      else ...[
        TextField(controller: shopName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Shop name')),
        TextField(controller: shopAddress, maxLines: 2, decoration: const InputDecoration(labelText: 'Shop address')),
        TextField(controller: shopPincode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Pincode', counterText: '')),
      ],
    ])));
  }

  Widget get _locationCard => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Your current location', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text('Captured automatically and required for every visit — it confirms you were actually at the shop.'),
    const SizedBox(height: 8),
    if (capturingLocation)
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Row(children: [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Capturing your location...'),
      ]))
    else if (position != null) ...[
      ClipRRect(borderRadius: BorderRadius.circular(8), child: ShopMap(
        shops: [Entry('me', {'name': 'Your location', 'latitude': position!.latitude, 'longitude': position!.longitude})],
        height: 160,
      )),
      const SizedBox(height: 8),
      Text('Location captured: ${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'),
    ] else if (locationError != null)
      Text(locationError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: capturingLocation ? null : _captureLocation, icon: const Icon(Icons.my_location), label: Text(position != null ? 'Recapture location' : 'Try again')),
  ])));

  Widget get _photoSection => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Item photo', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    if (photoBytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photoBytes!, height: 150, fit: BoxFit.cover))
    else Container(height: 90, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add_a_photo_outlined)),
    const SizedBox(height: 8),
    Text(uploading == 'photo' ? 'Uploading...' : photoReady ? 'Photo uploaded' : 'Required: not uploaded yet'),
    Wrap(spacing: 8, children: [
      OutlinedButton.icon(onPressed: busy || uploading != null ? null : () => pickPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose photo')),
      if (!kIsWeb) OutlinedButton.icon(onPressed: busy || uploading != null ? null : () => pickPhoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo')),
    ]),
  ])));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New field entry')),
    body: Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _shopSection,
        const SizedBox(height: 12),
        _locationCard,
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Item', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: itemName, decoration: const InputDecoration(labelText: 'Item name')),
          TextField(controller: itemPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
          TextField(controller: itemStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')),
        ]))),
        const SizedBox(height: 12),
        _photoSection,
        if (errors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Please fix the following before submitting:', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final e in errors) Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        const SizedBox(height: 16),
        FilledButton(onPressed: busy || uploading != null ? null : submit, child: Text(busy ? 'Submitting...' : 'Submit for approval')),
      ]),
    )))),
  );

  @override
  void dispose() {
    for (final c in [shopName, shopAddress, shopPincode, itemName, itemPrice, itemStock]) {
      c.dispose();
    }
    super.dispose();
  }
}
