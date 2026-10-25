import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/staff_auto_approve_switch.dart';

void main() {
  Future<List<bool>> show(WidgetTester tester, {required bool value}) async {
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StaffAutoApproveSwitch(staffName: 'Kiran Kumar', value: value, onChanged: (enabled) async => changes.add(enabled)),
      ),
    ));
    return changes;
  }

  testWidgets('off by default; turning auto-approve on asks first, and Cancel leaves it off', (tester) async {
    final changes = await show(tester, value: false);
    expect(find.text('Off: what they add waits for your approval.'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Auto-approve for Kiran Kumar?'), findsOneWidget);
    expect(find.textContaining('without the Google check'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auto-approve-confirm')));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(find.text('Auto-approve is on for Kiran Kumar.'), findsOneWidget);
  });

  testWidgets('turning it off needs no question', (tester) async {
    final changes = await show(tester, value: true);
    expect(find.text('On: vendors and services they add go live at once.'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(changes, [false]);
    expect(find.text('Auto-approve for Kiran Kumar?'), findsNothing);
  });
}
