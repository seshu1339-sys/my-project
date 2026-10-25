import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/my_numbers_card.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 6); // 26 Oct in India
  const records = [
    Entry('v1~2026-10-26', {'ownerId': 'v1', 'day': '2026-10-26', 'counts': {'shop_call': 3, 'shop_directions': 1}}),
    Entry('v1~2026-10-21', {'ownerId': 'v1', 'day': '2026-10-21', 'counts': {'shop_call': 2}}),
    Entry('v1~2026-10-10', {'ownerId': 'v1', 'day': '2026-10-10', 'counts': {'shop_call': 10, 'shop_whatsapp': 4}}),
    Entry('v1~2026-08-01', {'ownerId': 'v1', 'day': '2026-08-01', 'counts': {'shop_call': 99}}),
  ];

  test('a vendor\'s own numbers of the last 7 and 30 days', () {
    expect(myNumbers(records, now: now, days: 7), {'shop_call': 5, 'shop_directions': 1});
    expect(myNumbers(records, now: now, days: 30), {'shop_call': 15, 'shop_directions': 1, 'shop_whatsapp': 4});
  });

  testWidgets('the card shows each number for 7 and 30 days, 0 when nothing was counted', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MyNumbersView(records: records, events: const ['shop_call', 'shop_whatsapp', 'staff_added'], now: now))));
    expect(find.text('Your numbers'), findsOneWidget);
    expect(find.text('Calls to your shop'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('my-number-shop_call-7'))).data, '5');
    expect(tester.widget<Text>(find.byKey(const ValueKey('my-number-shop_call-30'))).data, '15');
    expect(tester.widget<Text>(find.byKey(const ValueKey('my-number-staff_added-30'))).data, '0');
  });
}
