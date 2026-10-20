import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/home_footer_badges.dart';

void main() {
  Future<Store> openStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    return store;
  }

  testWidgets(
    'every badge shares the same icon size from the group\'s own main (section_footerBadges), ignoring any stale per-badge iconSize',
    (tester) async {
      final store = await openStore();
      await store.save(
        'settings',
        const Entry('section_footerBadges', {'iconSize': 40.0}),
      );
      // A stale per-badge iconSize (as if left over from before the group
      // was consolidated) must have no effect -- size lives only on the
      // shared main now.
      await store.save(
        'settings',
        const Entry('section_footerBadge2', {'iconSize': 12.0}),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeFooterBadges(settings: store.entries('settings')),
          ),
        ),
      );
      await tester.pump();

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(icons, hasLength(6));
      expect(icons.every((icon) => icon.size == 40.0), isTrue);
    },
  );

  testWidgets(
    'the whole group hides when the shared main is set not visible, even if individual badges are still visible',
    (tester) async {
      final store = await openStore();
      await store.save(
        'settings',
        const Entry('section_footerBadges', {'visible': false}),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeFooterBadges(settings: store.entries('settings')),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Icon), findsNothing);
    },
  );
}
