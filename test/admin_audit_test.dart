import 'package:ecommerce_app/modules/flash/admin_flash_settings.dart';
import 'package:ecommerce_app/modules/flash/flash_data.dart';
import 'package:ecommerce_app/modules/photolimits/admin_item_photos.dart';
import 'package:ecommerce_app/modules/plans/admin_plans.dart';
import 'package:ecommerce_app/modules/plans/plan_model.dart';
import 'package:ecommerce_app/modules/staffareas/admin_staff_areas.dart';
import 'package:ecommerce_app/modules/staffareas/staff_area_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The admin panel check (owner, 7 Nov 2026): every option the owner named is there, in plain words, in its place, and fits a phone.
void main() {
  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('Plans (width $width): price, years, extra photos, km, Today\'s Offers boxes; free photos; where the other settings are', (tester) async {
      size(tester, Size(width, 2400));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminPlansView(
            plans: const [SubscriptionPlan(id: 'g', name: 'Gold', price: 2000, durationMonths: 36, active: true, tier: 'gold', extraPhotos: 6, radiusKm: 15)],
            gates: const {},
            onSave: (_) async {},
            onGate: (_, _) async {},
            onFreeLimit: (_) async {},
            onFreePhotos: (_) async {},
          ),
        ),
      ));
      expect(find.textContaining("2 Today's Offers boxes"), findsOneWidget);
      expect(find.textContaining('reach 15 km'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-free-photos-edit')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('plan-related-settings')), 300);
      for (final where in ['Ads > Common settings', 'Settings > Item photos', 'Flash > Settings', 'Staff Areas > Settings']) {
        expect(find.textContaining(where), findsOneWidget, reason: where);
      }
      await tester.scrollUntilVisible(find.byKey(const ValueKey('plan-add')), -300);
      await tester.tap(find.byKey(const ValueKey('plan-add')));
      await tester.pumpAndSettle();
      for (final label in ['Plan name', 'Price (₹)', 'How long the plan runs', 'Plan type (Silver, Gold, Platinum, Diamond or Premium)', 'Extra photos', 'Reach (km)', 'Items the vendor may list', "Today's Offers boxes"]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Years'), findsOneWidget);
      // A new plan's boxes follow its kind until the admin types a number.
      expect(tester.widget<TextFormField>(find.byKey(const ValueKey('plan-offer-boxes'))).controller!.text, '5');
      await tester.tap(find.byKey(const ValueKey('plan-tier')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Silver').last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(find.byKey(const ValueKey('plan-offer-boxes'))).controller!.text, '1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Staff Areas > Settings (width $width): targets each day, week and month for 4 measures, rate days, missed days', (tester) async {
      size(tester, Size(width, 2400));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: StaffAreaSettingsForm(settings: const StaffAreaSettings(), onSave: (_) async => null))));
      for (final words in ['Each day', 'Each week', 'Each month', 'Live photos (rate updates with a live camera photo)', 'Shops visited (different shops with a live-photo rate update)', 'New vendors linked', 'New Premium (paid) vendors linked']) {
        expect(find.text(words), findsOneWidget, reason: words);
      }
      for (final p in ['daily', 'weekly', 'monthly']) {
        for (final m in ['Photo', 'Shop', 'Vendor', 'PaidVendor']) {
          expect(find.byKey(ValueKey('staff-target-$p-$m')), findsOneWidget);
        }
      }
      expect(find.text('Missed days a month that stop the staff ID'), findsOneWidget);
      expect(find.text('Rate update days a week'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Settings > Item photos (width $width): photo rules and the own-photo categories', (tester) async {
      size(tester, Size(width, 1200));
      final changed = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OwnPhotoCategoriesView(categories: const [('sarees', 'Sarees', true), ('veg', 'Vegetables', false)], onChanged: (id, on) async => changed.add('$id $on')),
        ),
      ));
      expect(find.text("Categories that need the vendor's own photo"), findsOneWidget);
      expect(find.text('Own photo required'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('own-photo-category-veg')));
      await tester.pump();
      expect(changed, ['veg true']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Flash > Settings (width $width): the office phone and WhatsApp come first', (tester) async {
      size(tester, Size(width, 2400));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminFlashSettings(config: FlashConfig.fromData(const {}), onSave: (_) async {}))));
      expect(find.text('Office phone and WhatsApp'), findsOneWidget);
      final phone = tester.getTopLeft(find.byKey(const ValueKey('flash-support-phone')));
      final limit = tester.getTopLeft(find.byKey(const ValueKey('flash-limit')));
      expect(phone.dy, lessThan(limit.dy), reason: 'the office numbers are at the top');
      expect(find.text('Office WhatsApp number'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
