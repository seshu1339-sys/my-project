import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin.dart';
import 'package:ecommerce_app/ui/animation_settings.dart';
import 'package:ecommerce_app/ui/home_rotating_pages.dart';
import 'package:ecommerce_app/ui/home_section_config.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';
import 'package:ecommerce_app/ui/section_animations.dart';
import 'package:ecommerce_app/ui/text_animation.dart';

List<Entry> _settings(Map<String, dynamic> animations, {Map<String, Map<String, dynamic>> sections = const {}}) => [
  for (final e in sections.entries) Entry('section_${e.key}', e.value),
  if (animations.isNotEmpty) Entry('animations', animations),
];

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

void main() {
  group('what the website uses', () {
    test('with no Animations record the site is exactly as it was (the part\'s own settings)', () {
      final settings = _settings({}, sections: {'categories': {'animation': 'slide', 'animationSpeed': 600}});
      final effective = effectiveSectionConfig(settings, 'categories');
      expect(effective.text('animation'), 'slide');
      expect(effective.data.containsKey('entranceMs'), isFalse, reason: 'the original 450 ms stays');
      expect(identical(effective, sectionConfig(settings, 'categories')), isTrue);
      expect(animationsEnabled(settings), isTrue);
    });

    test('the four home sections start with a simple animation of their own until the admin chooses another', () {
      expect(homeSectionDefaults, {'scrollingText': 'marquee', 'notice': 'fade', 'promo': 'slideUp', 'boxes': 'fade', 'ads': 'fade'});
      for (final part in homeSectionDefaults.entries) {
        expect(effectiveSectionConfig(const [], part.key).text('animation'), part.value, reason: part.key);
      }
      // anything the admin chose wins over the start value, including None
      expect(effectiveSectionConfig(_settings({'promo_type': 'zoomIn'}), 'promo').text('animation'), 'zoomIn');
      expect(effectiveSectionConfig(_settings({'boxes_type': 'none'}), 'boxes').text('animation'), 'none');
      expect(effectiveSectionConfig(_settings({}, sections: {'promo': {'animation': 'none'}}), 'promo').text('animation'), 'none');
      expect(effectiveSectionConfig(_settings({'enabled': 'false'}), 'promo').text('animation'), 'none', reason: 'the global switch still turns it off');
      // other parts are not given one
      expect(effectiveSectionConfig(const [], 'categories').text('animation'), '');
    });

    test('the global switch turns every animation off, including banner changes and animated texts', () {
      final settings = _settings(
        {'enabled': 'false'},
        sections: {'promo': {'animation': 'slide', 'animationType': 'flip', 'textAnimation': 'zoom', 'headingAnimation': 'bounce', 'height': 300}},
      );
      final effective = effectiveSectionConfig(settings, 'promo');
      expect(effective.text('animation'), 'none');
      for (final key in ['animationType', 'textAnimation', 'headingAnimation']) {
        expect(effective.data.containsKey(key), isFalse, reason: key);
      }
      expect(effective.number('height'), 300, reason: 'nothing else changes');
      expect(animationsEnabled(settings), isFalse);
    });

    test('one part can be switched off while the others keep theirs', () {
      final settings = _settings({'categories_enabled': 'false'}, sections: {'categories': {'animation': 'fade'}, 'popular': {'animation': 'fade'}});
      expect(effectiveSectionConfig(settings, 'categories').text('animation'), 'none');
      expect(effectiveSectionConfig(settings, 'popular').text('animation'), 'fade');
    });

    test('type: this part\'s choice, else its own setting, else the default for all', () {
      final settings = _settings(
        {'popular_type': 'zoom', 'defaultType': 'fade'},
        sections: {'popular': {'animation': 'slide'}, 'categories': {'animation': 'slide'}, 'nearby': {}},
      );
      expect(effectiveSectionConfig(settings, 'popular').text('animation'), 'zoom');
      expect(effectiveSectionConfig(settings, 'categories').text('animation'), 'slide');
      expect(effectiveSectionConfig(settings, 'nearby').text('animation'), 'fade');
      expect(effectiveSectionConfig(settings, 'header').text('animation'), 'fade');
      // an unknown type is ignored
      expect(effectiveSectionConfig(_settings({'popular_type': 'spin'}, sections: {'popular': {'animation': 'slide'}}), 'popular').text('animation'), 'slide');
    });

    test('speed 1 (slow) to 10 (fast) sets how long an entrance takes; a part\'s own speed beats the default', () {
      expect(entranceMillis(1), greaterThan(entranceMillis(5)));
      expect(entranceMillis(5), greaterThan(entranceMillis(10)));
      expect(entranceMillis(10), 300);
      final settings = _settings({'defaultSpeed': 10, 'popular_speed': 1});
      expect(effectiveSectionConfig(settings, 'popular').number('entranceMs'), entranceMillis(1));
      expect(effectiveSectionConfig(settings, 'categories').number('entranceMs'), entranceMillis(10));
      expect(effectiveSectionConfig(settings, 'categories').number('animationSpeed'), 10, reason: 'a rotating banner uses the same speed');
      expect(effectiveSectionConfig(_settings({'defaultSpeed': 11}), 'popular').data.containsKey('entranceMs'), isFalse, reason: 'out of range is ignored');
    });

    test('a banner or ad can be given how its pictures change; other parts ignore it', () {
      final settings = _settings({'promo_rotation': 'cube', 'categories_rotation': 'cube'}, sections: {'promo': {}, 'categories': {}});
      expect(effectiveSectionConfig(settings, 'promo').text('animationType'), 'cube');
      expect(effectiveSectionConfig(settings, 'categories').data.containsKey('animationType'), isFalse);
      expect(PromoMotion.from(effectiveSectionConfig(settings, 'promo'))?.type, PromoAnimation.cube);
      expect(PromoMotion.from(effectiveSectionConfig(_settings({'enabled': 'false'}, sections: {'promo': {'animationType': 'cube'}}), 'promo')), isNull,
          reason: 'switched off: a plain swipe');
    });

    test('the admin\'s forms still read the raw record, so Animations values are never copied into a part\'s settings', () {
      final settings = _settings({'popular_type': 'zoom', 'popular_speed': 3}, sections: {'popular': {'height': 120}});
      expect(sectionConfig(settings, 'popular').data, {'height': 120});
      expect(effectiveSectionConfig(settings, 'popular').text('animation'), 'zoom');
    });
  });

  group('the page actually follows a change', () {
    Widget page(Store store) => MaterialApp(
      home: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Scaffold(
          body: LayoutSection(layout: layoutFor(context, store.entries('settings'), 'categories'), child: const Text('Categories here')),
        ),
      ),
    );

    SectionAnimation? entrance(WidgetTester tester) {
      final found = find.byType(SectionAnimation);
      return found.evaluate().isEmpty ? null : tester.widget<SectionAnimation>(found.first);
    }

    testWidgets('switching a part on, changing its speed and switching it off all show on the open page at once', (tester) async {
      final store = await _store();
      store.catalog['settings'] = [for (final e in store.catalog['settings']!) if (!e.id.startsWith('section_') && e.id != 'animations') e];
      await tester.pumpWidget(page(store));
      expect(entrance(tester), isNull, reason: 'no animation chosen yet: the page is as it always was');

      await store.save('settings', const Entry('animations', {'categories_type': 'fade', 'categories_speed': 10}));
      await tester.pump();
      var running = entrance(tester);
      expect(running, isNotNull);
      expect(running!.millis, entranceMillis(10));
      await tester.pumpAndSettle();

      await store.save('settings', const Entry('animations', {'categories_type': 'zoom', 'categories_speed': 1}));
      await tester.pump();
      running = entrance(tester);
      expect(running!.millis, entranceMillis(1), reason: 'the new speed is used');
      // the animation starts over: the text is not yet fully visible
      expect(tester.widget<Opacity>(find.ancestor(of: find.text('Categories here'), matching: find.byType(Opacity)).first).opacity, lessThan(1));
      await tester.pumpAndSettle();

      await store.save('settings', const Entry('animations', {'categories_type': 'zoom', 'enabled': 'false'}));
      await tester.pump();
      expect(entrance(tester), isNull, reason: 'global off');
      expect(find.text('Categories here'), findsOneWidget);
    });

    testWidgets('a part\'s own setting keeps working when the Animations record says nothing about it', (tester) async {
      final store = await _store();
      await store.save('settings', const Entry('section_categories', {'animation': 'slide'}));
      await store.save('settings', const Entry('animations', {'popular_type': 'zoom'}));
      await tester.pumpWidget(page(store));
      final running = tester.widget<SectionAnimation>(find.byType(SectionAnimation).first);
      expect(running.millis, 450);
    });

    testWidgets('zoom in is a real entrance (starts smaller, ends full size)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: applyEntranceAnimation(const Entry('x', {'animation': 'zoom', 'entranceMs': 600}), const SizedBox(width: 100, height: 100, child: Text('z'))),
      ));
      Transform zoom() => tester.widget<Transform>(find.ancestor(of: find.text('z'), matching: find.byType(Transform)).first);
      expect(zoom().transform.storage[0], closeTo(.85, .02));
      await tester.pumpAndSettle();
      expect(zoom().transform.storage[0], closeTo(1, .001));
    });

    testWidgets('animated texts start over when their type changes', (tester) async {
      Widget text(String type) => MaterialApp(home: animatedText(Entry('t', {'textAnimation': type}), 'textAnimation', const Text('Big Savings')));
      await tester.pumpWidget(text('fade'));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.ancestor(of: find.text('Big Savings'), matching: find.byType(Opacity)).first).opacity, 1);
      await tester.pumpWidget(text('slideUp'));
      expect(tester.widget<Opacity>(find.ancestor(of: find.text('Big Savings'), matching: find.byType(Opacity)).first).opacity, lessThan(1), reason: 'the new animation begins at once');
    });
  });

  group('Settings -> Animations form', () {
    Future<Store> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1300, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _store();
      await tester.pumpWidget(MaterialApp(home: AdminPage(store: store)));
      await tester.pump();
      DefaultTabController.of(tester.element(find.byType(TabBar).first)).animateTo(7);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-animations')));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('it sits between Theme and Scrolling Text and lists every part of the page', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('anim-global-enabled')), findsOneWidget);
      for (final part in animationParts.keys) {
        expect(find.byKey(ValueKey('anim-card-$part'), skipOffstage: false), findsOneWidget, reason: part);
      }
      final order = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.key as ValueKey<String>?)?.value).whereType<String>().toList();
      expect(order.indexOf('settings-animations'), order.indexOf('settings-theme') + 1);
      expect(order.indexOf('settings-scrollingText'), order.indexOf('settings-animations') + 1);
    });

    testWidgets('turning a part off, choosing a type and a speed, then saving writes the Animations record', (tester) async {
      final store = await open(tester);
      Future<void> pick(Finder dropdown, String label) async {
        await tester.ensureVisible(dropdown);
        await tester.pump();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await pick(find.byKey(const ValueKey('anim-default-type')), 'Fade');
      await pick(find.byKey(const ValueKey('anim-default-speed')), '10 (fastest)');
      await tester.ensureVisible(find.byKey(const ValueKey('anim-categories-enabled')));
      await tester.tap(find.byKey(const ValueKey('anim-categories-enabled')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('anim-save')));
      await tester.tap(find.byKey(const ValueKey('anim-save')));
      await tester.pumpAndSettle();
      final saved = store.entries('settings').firstWhere((e) => e.id == 'animations');
      expect(saved.text('defaultType'), 'fade');
      expect(saved.data['defaultSpeed'], 10);
      expect(saved.text('categories_enabled'), 'false');
      expect(saved.data.containsKey('enabled'), isFalse, reason: 'still on globally');
      expect(effectiveSectionConfig(store.entries('settings'), 'categories').text('animation'), 'none');
      expect(effectiveSectionConfig(store.entries('settings'), 'popular').text('animation'), 'fade');
    });

    testWidgets('the global switch greys out the parts, and switching it back keeps their choices', (tester) async {
      final store = await open(tester);
      await tester.tap(find.byKey(const ValueKey('anim-global-enabled')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('anim-default-type')), findsNothing);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('anim-header-enabled'), skipOffstage: false)).onChanged, isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('anim-save')));
      await tester.tap(find.byKey(const ValueKey('anim-save')));
      await tester.pumpAndSettle();
      expect(animationsEnabled(store.entries('settings')), isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('anim-global-enabled')));
      await tester.tap(find.byKey(const ValueKey('anim-global-enabled')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('anim-default-type')), findsOneWidget);
    });

    testWidgets('the Try it box plays the chosen entrance', (tester) async {
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('anim-preview-play')));
      await tester.tap(find.byKey(const ValueKey('anim-preview-play')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SectionAnimation), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
