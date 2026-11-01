import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/android_home.dart';
import 'package:ecommerce_app/ui/admin_android_home.dart';

void main() {
  testWidgets('Settings > Android App: every part has its place number, arrows and a show switch; Save keeps them', (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAndroidHomePage(store: store))));
    await tester.pumpAndSettle();
    for (final p in androidHomeParts) {
      expect(find.byKey(ValueKey('android-part-$p')), findsOneWidget, reason: p);
      expect(find.byKey(ValueKey('android-show-$p')), findsOneWidget, reason: p);
    }
    expect(find.byKey(const ValueKey('android-show-ad-boxes')), findsOneWidget);
    expect(find.byKey(const ValueKey('android-ad-slots')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('android-place-ads'))).data, '1');
    // move "Shops" to the top, hide "Fresh today", set 3 ad boxes
    for (var i = 0; i < androidHomeParts.length; i++) {
      await tester.tap(find.byKey(const ValueKey('android-up-nearby')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('android-show-quickFresh')));
    await tester.enterText(find.byKey(const ValueKey('android-ad-slots')), '3');
    await tester.tap(find.byKey(const ValueKey('save-android-home')));
    await tester.pumpAndSettle();
    final saved = AndroidHomeConfig.from(store.entries('settings'));
    expect(saved.adSlots, 3);
    expect(saved.order.first, 'nearby');
    expect(saved.hidden, {'quickFresh'});
    expect(saved.showAds, true);
    expect(tester.widget<Text>(find.byKey(const ValueKey('android-place-nearby'))).data, '1');
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
