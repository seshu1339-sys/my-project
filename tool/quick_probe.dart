// Manual check (not part of the apps): shows the Quick Add screens of the vendor and staff apps on a real Android
// screen with fake data, no sign-in and no network, so their layout can be checked on a phone-sized display.
//   flutter run -t tool/quick_probe.dart --flavor vendor
import 'dart:typed_data';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/places.dart';
import 'package:ecommerce_app/ui/quick_add.dart';
import 'package:flutter/material.dart';

const _vendor = Entry('v1', {
  'role': 'vendor', 'code': 'VN001', 'name': 'Ramu', 'active': true, 'shopLocked': true,
  'locationTown': 'Rajahmundry', 'locationDistrict': 'East Godavari', 'locationPincode': '533101',
  'shopLatitude': 17.0005, 'shopLongitude': 81.804,
});
const _newVendor = Entry('v2', {'role': 'vendor', 'code': 'VN002', 'name': 'New', 'active': true, 'shopLocked': false});
const _staff = Entry('s1', {'role': 'staff', 'code': 'ST001', 'name': 'Ravi', 'active': true});

// a small green square stands in for a photo
final _photo = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.init();
  store.catalog['categories'] = [
    for (final (i, name) in ['Fresh & Vegetables', 'Fruits', 'Dairy & Bakery', 'Rice, Dal & Grains', 'Snacks & Beverages', 'Electronics', 'Clothes', 'Books'].indexed)
      Entry('cat-$i', {'name': name, 'order': i, 'parentId': ''}),
  ];
  final env = QuickEnv(
    locate: () async => const QuickFix(17.0006, 81.804),
    findPlace: (lat, lng) async => const Place(name: 'Rajahmundry', district: 'East Godavari', state: 'Andhra Pradesh', pincode: '533101', village: false, latitude: 17, longitude: 81.8, town: 'Rajahmundry'),
    pick: (source) async => QuickPhotoResult('p', _photo),
    call: (name, data) async => {},
  );
  final now = DateTime.now();
  final items = [
    Entry('a', {'name': 'Tomatoes', 'price': 30.0, 'unit': 'per kg', 'categoryName': 'Fresh & Vegetables', 'locationName': 'Rajahmundry', 'status': 'approved', 'startsAt': now.subtract(const Duration(minutes: 5)), 'expiresAt': now.add(const Duration(hours: 2, minutes: 15)), 'durationUnit': 'hours', 'durationValue': 3}),
    Entry('b', {'name': 'Mangoes', 'price': 90.0, 'unit': 'per dozen', 'categoryName': 'Fruits', 'locationName': 'Rajahmundry', 'status': 'pending', 'durationUnit': 'days', 'durationValue': 1}),
  ];
  Widget page(Widget child) => child;
  final screens = <String, WidgetBuilder>{
    'Vendor: shop not set yet': (c) => Scaffold(appBar: AppBar(title: const Text('V Loca Market')), body: ListView(padding: const EdgeInsets.all(16), children: [QuickAddPanel(store: store, account: _newVendor, env: env, usedToday: 0, dailyLimit: 6)])),
    'Vendor: set shop location': (c) => QuickShopSetupPage(store: store, account: _newVendor, env: env),
    'Vendor: home (locked, 2 of 6)': (c) => Scaffold(appBar: AppBar(title: const Text('V Loca Market')), body: ListView(padding: const EdgeInsets.all(16), children: [QuickAddPanel(store: store, account: _vendor, env: env, usedToday: 2, dailyLimit: 6)])),
    'Vendor: categories': (c) => QuickCategoryPage(store: store, account: _vendor, env: env),
    'Vendor: add up to 5 items': (c) => QuickBatchFormPage(store: store, account: _vendor, category: const Entry('cat-0', {'name': 'Fresh & Vegetables'}), env: env),
    'Staff: add item': (c) => QuickItemFormPage(store: store, account: _staff, category: const Entry('cat-1', {'name': 'Fruits'}), env: env),
    'My Items': (c) => QuickMyItemsPage(store: store, account: _vendor, stream: Stream.value(items), env: env),
  };
  runApp(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B7A2E)),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Quick Add probe')),
          body: ListView(
            children: [
              for (final entry in screens.entries)
                ListTile(
                  key: ValueKey(entry.key),
                  title: Text(entry.key),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: entry.value)),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
