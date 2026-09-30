import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/field.dart';

class _RecordingStore extends Store {
  _RecordingStore() : super(live: true);
  int calls = 0;
  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    calls++;
    return {'status': 'pending', 'submissionId': 'fake'};
  }
}

List<String> errors({
  bool useExistingShop = false,
  bool hasExistingShop = false,
  String shopName = 'Ramu Stores',
  String shopAddress = '12 Market Road',
  String shopPincode = '560001',
  String itemName = 'Rice 5kg',
  String itemPrice = '250',
  String itemStock = '40',
  bool hasPhoto = true,
  bool hasLocation = true,
}) => fieldEntryErrors(
  useExistingShop: useExistingShop, hasExistingShop: hasExistingShop,
  shopName: shopName, shopAddress: shopAddress, shopPincode: shopPincode,
  itemName: itemName, itemPrice: itemPrice, itemStock: itemStock,
  hasPhoto: hasPhoto, hasLocation: hasLocation,
);

void main() {
  test('a complete new-shop entry has no errors', () => expect(errors(), isEmpty));

  test('a complete existing-shop entry has no errors', () => expect(errors(useExistingShop: true, hasExistingShop: true), isEmpty));

  test('an existing-shop entry with no shop chosen is blocked', () {
    expect(errors(useExistingShop: true, hasExistingShop: false), ['Choose a shop.']);
  });

  test('a new shop requires name, address and pincode', () {
    expect(errors(shopName: ' '), ['Enter the shop name.']);
    expect(errors(shopAddress: 'no'), ['Enter the shop address.']);
    expect(errors(shopPincode: '123'), ['Enter a valid six-digit pincode.']);
  });

  test('the item needs a name, a valid price and a whole-number stock', () {
    expect(errors(itemName: 'R'), ['Enter the item name.']);
    expect(errors(itemPrice: 'abc'), ['Enter a valid price.']);
    expect(errors(itemPrice: '-5'), ['Enter a valid price.']);
    expect(errors(itemStock: '1.5'), ['Enter the stock quantity as a whole number.']);
    expect(errors(itemStock: '-1'), ['Enter the stock quantity as a whole number.']);
  });

  test('the photo and GPS location are mandatory and reported separately', () {
    expect(errors(hasPhoto: false), ['Take or choose a photo of the item.']);
    expect(errors(hasLocation: false), ["Capture the shop's GPS location."]);
    expect(errors(hasPhoto: false, hasLocation: false), hasLength(2));
  });

  testWidgets('the existing/new shop toggle shows the right fields, and blocks submission when incomplete', (tester) async {
    final store = _RecordingStore();
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: FieldEntryForm(store: store)));
    await tester.pump();

    // Defaults to an existing-shop dropdown, not the new-shop fields.
    expect(find.text('Choose the shop you are visiting'), findsOneWidget);
    expect(find.text('Shop name'), findsNothing);

    await tester.tap(find.text('New shop'));
    await tester.pump();
    expect(find.text('Choose the shop you are visiting'), findsNothing);
    expect(find.text('Shop name'), findsOneWidget);
    expect(find.text('Shop address'), findsOneWidget);
    expect(find.text('Pincode'), findsOneWidget);

    // Geolocator is never mocked in this test, so GPS capture fails and the
    // form is blocked on that alone even once every other field is valid —
    // the same behavior vendor_test.dart already relies on for
    // VendorRegistrationForm's identical auto-capture-on-open pattern.
    await tester.enterText(find.widgetWithText(TextField, 'Shop name'), 'Ramu Stores');
    await tester.enterText(find.widgetWithText(TextField, 'Shop address'), '12 Market Road');
    await tester.enterText(find.widgetWithText(TextField, 'Pincode'), '560001');
    await tester.enterText(find.widgetWithText(TextField, 'Item name'), 'Rice 5kg');
    await tester.enterText(find.widgetWithText(TextField, 'Price'), '250');
    await tester.enterText(find.widgetWithText(TextField, 'Stock quantity'), '40');
    await tester.tap(find.text('Submit for approval'));
    await tester.pump();

    expect(find.text("• Capture the shop's GPS location."), findsOneWidget);
    expect(find.text('• Take or choose a photo of the item.'), findsOneWidget);
    expect(store.calls, 0, reason: 'nothing is submitted while required fields are missing');
  });
}
