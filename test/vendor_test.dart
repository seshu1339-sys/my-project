import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/vendor.dart';

class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  int registrations = 0;
  @override
  Future<String> registerVendor({
    required String ownerName,
    required String phone,
    required String name,
    required String shopCategory,
    required String address,
    required String pincode,
    required String description,
    required double latitude,
    required double longitude,
  }) async {
    registrations++;
    return 'pending';
  }
}

List<String> errors({
  String owner = 'Ravi Kumar',
  String phone = '+91 98765 43210',
  String shop = 'Ravi Stores',
  String category = 'Grocery',
  String address = '12 MG Road',
  String pincode = '560001',
  String description = 'Fresh vegetables daily',
  bool vendorPhoto = true,
  bool shopPhoto = true,
  bool location = true,
}) => vendorApplicationErrors(
  ownerName: owner, phone: phone, shopName: shop, shopCategory: category, address: address,
  pincode: pincode, description: description, hasVendorPhoto: vendorPhoto, hasShopPhoto: shopPhoto,
  hasLocation: location,
);

void main() {
  test('a complete application with both photos has no errors', () => expect(errors(), isEmpty));

  test('every required field blocks submission', () {
    expect(errors(owner: ' '), hasLength(1));
    expect(errors(phone: 'abc'), hasLength(1));
    expect(errors(shop: ''), hasLength(1));
    expect(errors(category: ''), hasLength(1));
    expect(errors(address: 'abc'), hasLength(1));
    expect(errors(pincode: '5600'), hasLength(1));
    expect(errors(description: 'short'), hasLength(1));
  });

  test('the shop GPS location is mandatory and reported separately', () {
    expect(errors(location: false), ["Capture the shop's GPS location."]);
    expect(errors(location: false, vendorPhoto: false), hasLength(2));
  });

  test('each photo is mandatory and reported separately', () {
    expect(errors(vendorPhoto: false), ['Upload a clear personal photo of the vendor.']);
    expect(errors(shopPhoto: false), ['Upload a photo of the actual shop.']);
    expect(errors(vendorPhoto: false, shopPhoto: false), hasLength(2));
  });

  testWidgets('the form lists every problem and sends nothing when incomplete', (tester) async {
    final store = _RecordingStore();
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VendorRegistrationForm(store: store, email: 'vendor@example.com'))));

    expect(find.text('vendor@example.com'), findsOneWidget);
    for (final label in ['Owner full name', 'Contact phone', 'Shop name', 'Shop address', 'Pincode', 'Shop description']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Vendor photo'), findsOneWidget);
    expect(find.text('Shop photo'), findsOneWidget);

    await tester.tap(find.text('Submit for approval'));
    await tester.pump();
    expect(find.text('• Upload a clear personal photo of the vendor.'), findsOneWidget);
    expect(find.text('• Upload a photo of the actual shop.'), findsOneWidget);
    expect(find.text("• Enter the owner's full name."), findsOneWidget);
    expect(store.registrations, 0);

    // All text fields filled, photos still missing: still blocked.
    final fields = find.byType(TextField);
    const values = ['Ravi Kumar', '9876543210', 'Ravi Stores', 'Grocery', '12 MG Road', '560001', 'Fresh vegetables daily'];
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
    await tester.tap(find.text('Submit for approval'));
    await tester.pump();
    expect(find.text("• Enter the owner's full name."), findsNothing);
    expect(find.text('• Upload a clear personal photo of the vendor.'), findsOneWidget);
    expect(store.registrations, 0);
  });

  testWidgets('a rejected applicant sees the reason and keeps their earlier details', (tester) async {
    final store = _RecordingStore();
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VendorRegistrationForm(
      store: store, email: 'vendor@example.com',
      previous: const {'status': 'rejected', 'decisionReason': 'Shop photo is blurry', 'ownerName': 'Ravi Kumar', 'name': 'Ravi Stores', 'vendorPhotoPath': 'a', 'shopPhotoPath': 'b'},
    ))));
    expect(find.textContaining('Shop photo is blurry'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Photo uploaded'), findsNWidgets(2));
  });
}
