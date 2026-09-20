import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';

/// Returns every reason the registration must not be submitted yet. Mirrors the
/// server-side checks in functions/domain.js so nothing incomplete is sent.
List<String> vendorApplicationErrors({
  required String ownerName,
  required String phone,
  required String shopName,
  required String shopCategory,
  required String address,
  required String pincode,
  required String description,
  required bool hasVendorPhoto,
  required bool hasShopPhoto,
}) {
  bool between(String v, int min, int max) => v.trim().length >= min && v.trim().length <= max;
  return [
    if (!between(ownerName, 2, 100)) "Enter the owner's full name.",
    if (!RegExp(r'^\+?[0-9][0-9 -]{6,17}$').hasMatch(phone.trim())) 'Enter a valid contact phone number.',
    if (!between(shopName, 2, 120)) 'Enter the shop name.',
    if (!between(shopCategory, 2, 80)) 'Enter the shop category.',
    if (!between(address, 5, 500)) 'Enter the shop address.',
    if (!RegExp(r'^\d{6}$').hasMatch(pincode.trim())) 'Enter a valid six-digit pincode.',
    if (!between(description, 10, 1000)) 'Describe the shop (at least 10 characters).',
    if (!hasVendorPhoto) 'Upload a clear personal photo of the vendor.',
    if (!hasShopPhoto) 'Upload a photo of the actual shop.',
  ];
}

class VendorPage extends StatefulWidget {
  const VendorPage({super.key, required this.store});
  final Store store;
  @override
  State<VendorPage> createState() => _VendorPageState();
}

class _VendorPageState extends State<VendorPage> {
  final paymentReference = TextEditingController();
  bool busy = false;
  Store get store => widget.store;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try { await action(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!store.live) return _demo();
    final user = store.user;
    if (user == null) return const SizedBox.shrink();
    final actions = [IconButton(tooltip: 'Log out', onPressed: store.logout, icon: const Icon(Icons.logout))];
    // The registration form only exists for a verified email address.
    if (!user.emailVerified) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vendor studio'), actions: actions),
        body: const _Message(title: 'Verify your email first', body: 'Sign out and use "Continue with email link" so we can verify your email. The vendor registration form opens after your email is verified.'),
      );
    }
    final uid = user.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Vendor studio'), actions: actions),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: store.firestore.collection('vendorApplications').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _Message(title: 'Could not load your application', body: 'Please check your connection and try again.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final application = snapshot.data!.data();
          final status = application?['status'];
          if (application == null || status == 'rejected') return VendorRegistrationForm(store: store, email: user.email ?? '', previous: application);
          if (status == 'pending') return _pending(application);
          if (status == 'payment_required') return _feePayment(application);
          if (status == 'payment_submitted') return const _Message(title: 'Payment submitted', body: 'Your payment reference was submitted for administrator confirmation.');
          if (status != 'approved') return _Message(title: 'Application $status', body: 'Await administrator review.');
          return VendorWorkspace(store: store, uid: uid);
        },
      ),
    );
  }

  Widget _pending(Map<String, dynamic> application) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(children: [
      const Icon(Icons.hourglass_top, size: 48),
      const SizedBox(height: 12),
      const Text('Pending Approval', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const Text('Your application is waiting for office or admin approval. You will be notified here as soon as it is reviewed.', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      const Text('Business features (adding products or materials, product photos, prices, stock and orders) stay locked until your application is approved.', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Card(child: ListTile(title: Text('${application['name']}'), subtitle: Text('${application['ownerName'] ?? ''} • ${application['shopCategory'] ?? ''}\n${application['address'] ?? ''} ${application['pincode'] ?? ''}'))),
    ]),
  ))));

  Widget _feePayment(Map<String, dynamic> application) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(children: [
      const Text('Vendor registration reviewed', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text('Administrator fee: ${application['feeAmount']}'),
      if ((application['decisionReason'] ?? '').toString().trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Administrator note: ${application['decisionReason']}')),
      const SizedBox(height: 8),
      const Text('Complete the vendor fee payment using the instructions provided by the administrator, then enter the payment reference below.'),
      TextField(controller: paymentReference, decoration: const InputDecoration(labelText: 'Payment reference')),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : () => run(() async { await store.submitVendorFeePayment(paymentReference.text.trim()); }), child: const Text('Submit payment reference')),
    ]),
  ))));

  Widget _demo() => Scaffold(appBar: AppBar(title: const Text('Vendor studio')), body: const Center(child: Text('Connect Firebase to apply and manage a vendor shop.')));
  @override
  void dispose() { paymentReference.dispose(); super.dispose(); }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title, body;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    const SizedBox(height: 12),
    Text(body, textAlign: TextAlign.center),
  ]))));
}

/// The full vendor + shop registration. Shown only after the email is verified,
/// and it cannot be submitted until every field and both photos are provided.
class VendorRegistrationForm extends StatefulWidget {
  const VendorRegistrationForm({super.key, required this.store, required this.email, this.previous});
  final Store store;
  final String email;
  final Map<String, dynamic>? previous;
  @override
  State<VendorRegistrationForm> createState() => _VendorRegistrationFormState();
}

class _VendorRegistrationFormState extends State<VendorRegistrationForm> {
  late final ownerName = TextEditingController(text: '${widget.previous?['ownerName'] ?? ''}');
  late final phone = TextEditingController(text: '${widget.previous?['phone'] ?? ''}');
  late final shopName = TextEditingController(text: '${widget.previous?['name'] ?? ''}');
  late final shopCategory = TextEditingController(text: '${widget.previous?['shopCategory'] ?? ''}');
  late final address = TextEditingController(text: '${widget.previous?['address'] ?? ''}');
  late final pincode = TextEditingController(text: '${widget.previous?['pincode'] ?? ''}');
  late final description = TextEditingController(text: '${widget.previous?['description'] ?? ''}');
  Uint8List? vendorBytes, shopBytes;
  // A rejected applicant may keep the photos already on file, or replace them.
  late bool vendorReady = widget.previous?['vendorPhotoPath'] != null;
  late bool shopReady = widget.previous?['shopPhotoPath'] != null;
  String? uploading;
  List<String> errors = const [];
  bool busy = false;

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> pick(String kind, ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() => uploading = kind);
      final bytes = await widget.store.uploadApplicationPhoto(kind, file);
      if (!mounted) return;
      setState(() {
        if (kind == 'vendorPhoto') { vendorBytes = bytes; vendorReady = true; } else { shopBytes = bytes; shopReady = true; }
        errors = const [];
      });
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  Future<void> submit() async {
    final problems = vendorApplicationErrors(
      ownerName: ownerName.text, phone: phone.text, shopName: shopName.text, shopCategory: shopCategory.text,
      address: address.text, pincode: pincode.text, description: description.text,
      hasVendorPhoto: vendorReady, hasShopPhoto: shopReady,
    );
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      await widget.store.registerVendor(
        ownerName: ownerName.text.trim(), phone: phone.text.trim(), name: shopName.text.trim(), shopCategory: shopCategory.text.trim(),
        address: address.text.trim(), pincode: pincode.text.trim(), description: description.text.trim(),
      );
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _photo({required String kind, required String title, required String hint, required Uint8List? bytes, required bool ready}) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    Text(hint),
    const SizedBox(height: 8),
    if (bytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, height: 150, fit: BoxFit.cover))
    else Container(height: 90, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)), child: Icon(ready ? Icons.check_circle : Icons.add_a_photo_outlined)),
    const SizedBox(height: 8),
    Text(uploading == kind ? 'Uploading...' : ready ? 'Photo uploaded' : 'Required: not uploaded yet'),
    Wrap(spacing: 8, children: [
      OutlinedButton.icon(onPressed: busy || uploading != null ? null : () => pick(kind, ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(kind == 'vendorPhoto' ? 'Choose vendor photo' : 'Choose shop photo')),
      if (!kIsWeb) OutlinedButton.icon(onPressed: busy || uploading != null ? null : () => pick(kind, ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: Text(kind == 'vendorPhoto' ? 'Take vendor photo' : 'Take shop photo')),
    ]),
  ])));

  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.previous == null ? 'Vendor registration' : 'Update your vendor application', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Your email is verified. Complete every field and upload both photos, then submit for office approval.'),
      if (widget.previous?['decisionReason'] != null && widget.previous?['status'] == 'rejected') Padding(padding: const EdgeInsets.only(top: 8), child: Text('Application rejected. Administrator reason: ${widget.previous!['decisionReason']}', style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 16),
      InputDecorator(decoration: const InputDecoration(labelText: 'Verified email', border: OutlineInputBorder()), child: Text(widget.email)),
      const SizedBox(height: 12),
      TextField(controller: ownerName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Owner full name')),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone')),
      TextField(controller: shopName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Shop name')),
      TextField(controller: shopCategory, decoration: const InputDecoration(labelText: 'Shop category', hintText: 'For example Grocery, Hardware')),
      TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Shop address')),
      TextField(controller: pincode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Pincode', counterText: '')),
      TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Shop description')),
      const SizedBox(height: 12),
      _photo(kind: 'vendorPhoto', title: 'Vendor photo', hint: 'A clear personal photo of the vendor (owner).', bytes: vendorBytes, ready: vendorReady),
      _photo(kind: 'shopPhoto', title: 'Shop photo', hint: 'A separate photo of the actual shop.', bytes: shopBytes, ready: shopReady),
      if (errors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Please fix the following before submitting:', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final e in errors) Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy || uploading != null ? null : submit, child: Text(busy ? 'Submitting...' : 'Submit for approval')),
    ]),
  ))));

  @override
  void dispose() {
    for (final c in [ownerName, phone, shopName, shopCategory, address, pincode, description]) { c.dispose(); }
    super.dispose();
  }
}

/// Business features. Only built once the application status is approved; the
/// server independently refuses every one of these actions for anyone else.
class VendorWorkspace extends StatefulWidget {
  const VendorWorkspace({super.key, required this.store, required this.uid});
  final Store store;
  final String uid;
  @override
  State<VendorWorkspace> createState() => _VendorWorkspaceState();
}

class _VendorWorkspaceState extends State<VendorWorkspace> {
  final docId = TextEditingController(), value = TextEditingController(), orderId = TextEditingController(), code = TextEditingController();
  final pName = TextEditingController(), pPrice = TextEditingController(), pStock = TextEditingController(), pUnit = TextEditingController(), pDescription = TextEditingController();
  String type = 'product';
  String? categoryId, productImageUrl;
  Uint8List? productImageBytes;
  bool busy = false;
  Store get store => widget.store;
  String get uid => widget.uid;
  void toast(Object message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message'))); }
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try { await action(); } catch (e) { toast(e); }
    if (mounted) setState(() => busy = false);
  }
  String published(String status) => status == 'approved' ? 'Published' : 'Pending administrator approval';

  Future<XFile?> pickImage() => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);

  Future<void> addProduct() async {
    final price = double.tryParse(pPrice.text.trim());
    final stock = int.tryParse(pStock.text.trim());
    if (pName.text.trim().length < 2) throw StateError('Enter the product or material name.');
    if (price == null || price < 0) throw StateError('Enter a valid price.');
    if (stock == null || stock < 0) throw StateError('Enter the stock quantity as a whole number.');
    final status = await store.submitVendorChange(type: 'newProduct', collection: 'products', docId: '', changes: {
      'name': pName.text.trim(), 'price': price, 'stock': stock,
      if (pUnit.text.trim().isNotEmpty) 'unit': pUnit.text.trim(),
      if (pDescription.text.trim().isNotEmpty) 'description': pDescription.text.trim(),
      if (categoryId != null) 'categoryId': categoryId,
      if (productImageUrl != null) 'imageUrl': productImageUrl,
    });
    for (final c in [pName, pPrice, pStock, pUnit, pDescription]) { c.clear(); }
    setState(() { productImageUrl = null; productImageBytes = null; categoryId = null; });
    toast(published(status));
  }

  Future<num?> askNumber(String title, String label, {required bool integer, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final ok = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label)),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Save'))],
    ));
    final text = controller.text.trim();
    controller.dispose();
    if (ok != true) return null;
    final parsed = integer ? int.tryParse(text) : double.tryParse(text);
    if (parsed == null || parsed < 0) throw StateError(integer ? 'Enter a whole number.' : 'Enter a valid number.');
    return parsed;
  }

  Widget _card(String title, List<Widget> children, {String? note}) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    if (note != null) Text(note),
    ...children,
  ])));

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Approved vendor workspace', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text('Your application is approved. Public changes are either published immediately by policy or held for administrator approval.'),
    const SizedBox(height: 20),
    _card('Add a product or material', [
      TextField(controller: pName, decoration: const InputDecoration(labelText: 'Product or material name')),
      TextField(controller: pPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
      TextField(controller: pStock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')),
      TextField(controller: pUnit, decoration: const InputDecoration(labelText: 'Unit (for example kg, bag, each)')),
      TextField(controller: pDescription, maxLines: 2, decoration: const InputDecoration(labelText: 'Product description')),
      DropdownButtonFormField<String>(
        initialValue: categoryId, isExpanded: true, decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final c in store.entries('categories')) DropdownMenuItem(value: c.id, child: Text(c.text('name')))],
        onChanged: (v) => setState(() => categoryId = v),
      ),
      const SizedBox(height: 8),
      if (productImageBytes != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(productImageBytes!, height: 120, fit: BoxFit.cover)),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: busy ? null : () => run(() async {
          final file = await pickImage();
          if (file == null) return;
          final bytes = await file.readAsBytes();
          final url = await store.upload(file, folder: 'vendorProducts/$uid');
          if (mounted) setState(() { productImageUrl = url; productImageBytes = bytes; });
        }), icon: const Icon(Icons.upload), label: const Text('Upload product photo')),
        FilledButton(onPressed: busy ? null : () => run(addProduct), child: const Text('Submit product')),
      ]),
    ]),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('products').where('ownerId', isEqualTo: uid).limit(100).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        return _card('My products and materials', [
          if (docs.isEmpty) const Text('No published products yet. Submitted products appear here once published.'),
          for (final doc in docs) ListTile(
            contentPadding: EdgeInsets.zero,
            leading: (doc.data()['imageUrl'] ?? '').toString().isEmpty ? const Icon(Icons.inventory_2_outlined) : SizedBox(width: 44, height: 44, child: Image.network('${doc.data()['imageUrl']}', fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))),
            title: Text('${doc.data()['name']}'),
            subtitle: Text('Price ${doc.data()['price']} • Stock ${doc.data()['stock'] ?? 0}'),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Update price', icon: const Icon(Icons.sell_outlined), onPressed: busy ? null : () => run(() async {
                final n = await askNumber('Update price', 'New price', integer: false, initial: '${doc.data()['price'] ?? ''}');
                if (n == null) return;
                toast(published(await store.submitVendorChange(type: 'price', collection: 'products', docId: doc.id, changes: {'price': n.toDouble()})));
              })),
              IconButton(tooltip: 'Update stock', icon: const Icon(Icons.inventory_outlined), onPressed: busy ? null : () => run(() async {
                final n = await askNumber('Update stock', 'Stock quantity', integer: true, initial: '${doc.data()['stock'] ?? 0}');
                if (n == null) return;
                toast(published(await store.submitVendorChange(type: 'stock', collection: 'products', docId: doc.id, changes: {'stock': n.toInt()})));
              })),
              IconButton(tooltip: 'Change photo', icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: busy ? null : () => run(() async {
                final file = await pickImage();
                if (file == null) return;
                final url = await store.upload(file, folder: 'vendorProducts/$uid');
                toast(published(await store.submitVendorChange(type: 'product', collection: 'products', docId: doc.id, changes: {'imageUrl': url})));
              })),
            ]),
          ),
        ]);
      },
    ),
    _card('Submit a product or shop change', [
      DropdownButton<String>(value: type, items: const [DropdownMenuItem(value: 'product', child: Text('Product detail')), DropdownMenuItem(value: 'price', child: Text('Price')), DropdownMenuItem(value: 'shop', child: Text('Shop detail'))], onChanged: (value) => setState(() => type = value!)),
      TextField(controller: docId, decoration: const InputDecoration(labelText: 'Product or shop ID')),
      TextField(controller: value, maxLines: 3, decoration: const InputDecoration(labelText: 'New value (for prices use a number)')),
      const SizedBox(height: 8),
      FilledButton(onPressed: busy ? null : () => run(() async {
        final field = type == 'price' ? 'price' : type == 'shop' ? 'description' : 'name';
        final newValue = type == 'price' ? double.tryParse(value.text) : value.text.trim();
        if (newValue == null || (newValue is String && newValue.isEmpty)) throw StateError('Enter a valid value.');
        final status = await store.submitVendorChange(type: type, collection: type == 'shop' ? 'shops' : 'products', docId: docId.text.trim(), changes: {field: newValue});
        toast(published(status));
      }), child: const Text('Submit change')),
    ]),
    _card('Verified purchase', [
      TextField(controller: orderId, decoration: const InputDecoration(labelText: 'Order ID')),
      TextField(controller: code, decoration: const InputDecoration(labelText: 'Six-digit customer code')),
      FilledButton(onPressed: busy ? null : () => run(() async {
        final position = await Geolocator.getCurrentPosition();
        await store.call('redeemPurchaseCode', {'orderId': orderId.text.trim(), 'code': code.text.trim(), 'latitude': position.latitude, 'longitude': position.longitude});
        toast('Verified purchase recorded');
      }), child: const Text('Verify purchase')),
    ], note: 'Enter the customer one-time code and the current shop location when the purchase is collected.'),
    // Orders carry the shops they include (shopIds), not a vendor id, and the rules
    // only let a vendor read orders containing its own shop.
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('vendors').doc(uid).snapshots(), builder: (_, vendor) {
      final shopId = vendor.data?.data()?['shopId'];
      if (shopId is! String) return const ListTile(leading: Icon(Icons.receipt_long), title: Text('Orders'), subtitle: Text('0 vendor orders'));
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('orders').where('shopIds', arrayContains: shopId).limit(50).snapshots(), builder: (_, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Orders'), subtitle: Text('${docs.length} vendor orders')),
          for (final doc in docs) _orderTile(doc),
        ]);
      });
    }),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: store.firestore.collection('vendorChanges').where('vendorId', isEqualTo: uid).limit(50).snapshots(), builder: (_, snapshot) {
      final docs = snapshot.data?.docs ?? const [];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(leading: const Icon(Icons.pending_actions), title: const Text('Change history'), subtitle: Text('${docs.length} submitted changes')),
        for (final doc in docs) ListTile(dense: true, title: Text('${doc.data()['type']} • ${doc.data()['newValue']?['name'] ?? doc.data()['docId']}'), subtitle: Text('${doc.data()['status']}${doc.data()['decisionReason'] != null && '${doc.data()['decisionReason']}'.isNotEmpty ? ' — ${doc.data()['decisionReason']}' : ''}')),
      ]);
    }),
  ]);

  Widget _orderTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final order = doc.data();
    final status = '${order['status']}';
    final lines = [for (final l in (order['lines'] as List? ?? const [])) '${(l as Map)['name']} × ${l['quantity']}'].join(', ');
    Widget action(String label, String next) => OutlinedButton(onPressed: busy ? null : () => run(() async { await store.updateVendorOrder(doc.id, next); toast('Order marked $next'); }), child: Text(label));
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Order ${doc.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.bold)),
      Text('$lines • Total ${order['total']}'),
      Text('${order['address']}'),
      Text('Payment: ${order['paymentMethod']} • ${order['paymentStatus']}'),
      Text('Status: $status'),
      Wrap(spacing: 8, children: [
        if (status == 'submitted') action('Confirm order', 'confirmed'),
        if (status == 'confirmed') action('Mark fulfilled', 'fulfilled'),
        if (status == 'submitted' || status == 'confirmed') action('Cancel order', 'cancelled'),
      ]),
    ])));
  }

  @override
  void dispose() {
    for (final c in [docId, value, orderId, code, pName, pPrice, pStock, pUnit, pDescription]) { c.dispose(); }
    super.dispose();
  }
}
