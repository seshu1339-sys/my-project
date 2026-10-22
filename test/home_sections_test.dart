import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/main.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_entry_list.dart';
import 'package:ecommerce_app/ui/admin_home_sections.dart';
import 'package:ecommerce_app/ui/ads_column.dart';
import 'package:ecommerce_app/ui/animation_settings.dart';
import 'package:ecommerce_app/ui/color_picker_field.dart';
import 'package:ecommerce_app/ui/entry_editor.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';
import 'package:ecommerce_app/ui/section_animations.dart';

Future<Store> _store({List<Entry> settings = const [], String town = ''}) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['settings'] = [...settings];
  store.catalog['promotions'] = const [
    Entry('c1', {'name': "Today's Offer", 'description': 'Fresh vegetables', 'placement': 'carousel', 'backgroundColor': '#16A34A', 'order': 1}),
    Entry('b1', {'name': 'Curated for you', 'description': 'Up to 30% OFF', 'placement': 'box', 'order': 2}),
    Entry('a1', {'name': 'Big Savings', 'placement': 'ad', 'order': 3}),
  ];
  store.catalog['ads'] = [];
  if (town.isNotEmpty) await store.setLocation('531116', town, town: town);
  return store;
}

Future<void> _show(WidgetTester tester, Store store, String part) async {
  tester.view.physicalSize = const Size(1300, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminHomeSectionPage(store: store, part: part))));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _pick(WidgetTester tester, Finder dropdown, String label) async {
  await tester.ensureVisible(dropdown);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(dropdown);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 700));
}

Finder _animationDropdown(String part) => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('anim-$part-'));

void main() {
  group('names as the customer sees them', () {
    test('the admin uses the same names as the website', () {
      expect(layoutComponents['notice'], "Today's Offers");
      expect(layoutComponents['promo'], "Today's Offers Box");
      expect(layoutComponents['ads'], 'Right Side Ads');
      expect(layoutComponents['boxes'], 'Right Side Ads: boxes below the ads');
      expect(externalLayoutComponents['tickerMarquee'], 'Scrolling Text');
      expect(animationParts['scrollingText'], 'Scrolling Text');
      expect(animationParts['notice'], "Today's Offers");
      expect(animationParts['promo'], "Today's Offers Box");
      expect(animationParts['ads'], 'Right Side Ads');
    });
  });

  group('the animation list', () {
    test('has exactly the animations asked for, one list for every section', () {
      expect(homeAnimations.values.toList(), ['Fade', 'Slide', 'Zoom', 'Bounce', 'Flip', 'Rotate', 'Pulse', 'Shake', 'Typewriter', 'Marquee', 'Slide Up', 'Slide Down', 'Zoom In', 'Zoom Out', 'None']);
      expect(entranceTypes, same(homeAnimations), reason: 'the Animations page uses the same list');
      expect(adAnimations, same(homeAnimations), reason: 'so do the Right Side Ads');
    });

    for (final type in homeAnimations.keys) {
      testWidgets('$type plays on a section without errors, from the first frame to the last', (tester) async {
        for (final t in [0.0, .2, .5, .8, 1.0]) {
          await tester.pumpWidget(MaterialApp(home: SizedBox(width: 400, height: 120, child: sectionAnimationFrame(type, t, const ColoredBox(color: Colors.green, child: Text('x'))))));
          expect(tester.takeException(), isNull, reason: '$type at $t');
        }
        await tester.pumpWidget(MaterialApp(home: SizedBox(width: 400, height: 120, child: SectionAnimation(type: type, millis: 300, child: const Text('x')))));
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('x'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('Fade starts invisible and ends fully visible; Zoom In starts small; None leaves the section alone', (tester) async {
      Future<double> opacityAt(String type, double t) async {
        await tester.pumpWidget(MaterialApp(home: sectionAnimationFrame(type, t, const Text('x'))));
        return tester.widgetList<Opacity>(find.byType(Opacity)).fold<double>(1, (a, o) => a * o.opacity);
      }

      expect(await opacityAt('fade', 0), 0);
      expect(await opacityAt('fade', 1), 1);
      await tester.pumpWidget(MaterialApp(home: sectionAnimationFrame('zoomIn', 0, const Text('x'))));
      expect(tester.widgetList<Transform>(find.byType(Transform)).any((t) => (t.transform.entry(0, 0) - .5).abs() < .01), isTrue, reason: 'Zoom In starts at half size');
      await tester.pumpWidget(MaterialApp(home: sectionAnimationFrame('none', .3, const Text('x'))));
      expect(find.byType(Opacity), findsNothing);
      expect(isRepeatingAnimation('pulse'), isTrue);
      expect(isRepeatingAnimation('fade'), isFalse);
    });
  });

  group('every section starts with one simple animation', () {
    test('and the website uses it until the admin chooses another', () {
      expect(effectiveSectionConfig(const [], 'notice').text('animation'), 'fade');
      expect(effectiveSectionConfig(const [], 'promo').text('animation'), 'slideUp');
      expect(effectiveSectionConfig(const [], 'ads').text('animation'), 'fade');
      expect(effectiveSectionConfig(const [], 'scrollingText').text('animation'), 'marquee');
      expect(AdsConfig.from(const []).animation, 'fade');
    });
  });

  group('one page per section', () {
    const parts = {
      'scrollingText': ('Scrolling Text', 'moving line'),
      'notice': ("Today's Offers", 'price chips'),
      'promo': ("Today's Offers Box", 'coloured boxes'),
      'ads': ('Right Side Ads', 'right-hand side'),
    };

    for (final e in parts.entries) {
      testWidgets('${e.value.$1}: says what it is, shows a preview, the animation list, the speed and the colours', (tester) async {
        final store = await _store();
        await _show(tester, store, e.key);
        expect(find.text(e.value.$1), findsWidgets);
        expect(find.textContaining(e.value.$2), findsWidgets, reason: 'what the part is on the website');
        expect(find.byKey(ValueKey('preview-box-${e.key}')), findsOneWidget);
        expect(find.byKey(ValueKey('play-${e.key}')), findsOneWidget);
        expect(_animationDropdown(e.key), findsOneWidget);
        for (final c in ['backgroundColor', 'textColor', 'borderColor']) {
          expect(find.byKey(ValueKey('color-${e.key}-$c')), findsOneWidget, reason: c);
        }
        expect(find.byKey(ValueKey(e.key == 'scrollingText' ? 'scroll-speed' : 'speed-${e.key}-${e.key == 'ads' ? 5 : 0}')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('the dropdown lists all the animations, and each section starts on its own', (tester) async {
      final store = await _store();
      await _show(tester, store, 'promo');
      expect(find.text('(Slide Up)'), findsOneWidget, reason: 'the preview names the animation it is playing');
      await tester.tap(_animationDropdown('promo'));
      await tester.pump(const Duration(milliseconds: 400));
      for (final name in homeAnimations.values) {
        expect(find.text(name), findsWidgets, reason: name);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("Today's Offers: the preview carries the town, and the chosen animation plays in it and is saved for that section only", (tester) async {
      final store = await _store(town: 'Narsipatnam');
      await _show(tester, store, 'notice');
      expect(find.text("Today's Narsipatnam Offers"), findsOneWidget);
      expect(tester.widget<SectionAnimation>(find.descendant(of: find.byKey(const ValueKey('preview-box-notice')), matching: find.byType(SectionAnimation))).type, 'fade');
      await _pick(tester, _animationDropdown('notice'), 'Bounce');
      expect(find.text('(Bounce)'), findsOneWidget);
      expect(tester.widget<SectionAnimation>(find.descendant(of: find.byKey(const ValueKey('preview-box-notice')), matching: find.byType(SectionAnimation))).type, 'bounce', reason: 'the preview plays the choice before saving');
      expect(effectiveSectionConfig(store.entries('settings'), 'notice').text('animation'), 'fade', reason: 'not saved yet');
      await tester.ensureVisible(find.byKey(const ValueKey('save-notice')));
      await tester.tap(find.byKey(const ValueKey('save-notice')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(effectiveSectionConfig(store.entries('settings'), 'notice').text('animation'), 'bounce');
      expect(effectiveSectionConfig(store.entries('settings'), 'promo').text('animation'), 'slideUp', reason: 'the other sections are not touched');
      expect(effectiveSectionConfig(store.entries('settings'), 'ads').text('animation'), 'fade');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("Today's Offers Box: animation, speed and colours are saved where the website reads them", (tester) async {
      final store = await _store();
      await _show(tester, store, 'promo');
      await _pick(tester, _animationDropdown('promo'), 'Zoom Out');
      await _pick(tester, find.byKey(const ValueKey('speed-promo-0')), '10 (fastest)');
      tester.widget<ColorPickerField>(find.byKey(const ValueKey('color-promo-backgroundColor'))).onChanged('#112233');
      tester.widget<ColorPickerField>(find.byKey(const ValueKey('color-promo-textColor'))).onChanged('#FFFFFF');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('save-promo')));
      await tester.tap(find.byKey(const ValueKey('save-promo')));
      await tester.pump(const Duration(milliseconds: 500));
      final doc = store.entries('settings').firstWhere((e) => e.id == 'animations');
      expect(doc.text('promo_type'), 'zoomOut');
      expect(doc.data['promo_speed'], 10);
      final website = effectiveSectionConfig(store.entries('settings'), 'promo');
      expect(website.text('animation'), 'zoomOut');
      expect(website.number('entranceMs'), entranceMillis(10));
      final layout = store.entries('settings').firstWhere((e) => e.id == 'section_promo');
      expect(layout.text('backgroundColor'), '#112233', reason: 'the same record the Layout page edits');
      expect(layout.text('textColor'), '#FFFFFF');
      expect(layout.data.containsKey('borderColor'), isFalse);
      // clearing a colour removes it again
      tester.widget<ColorPickerField>(find.byKey(const ValueKey('color-promo-backgroundColor'))).onChanged('');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-promo')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(store.entries('settings').firstWhere((e) => e.id == 'section_promo').data.containsKey('backgroundColor'), isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('every page fits a phone screen', (tester) async {
      for (final part in ['scrollingText', 'notice', 'promo', 'ads']) {
        final store = await _store(town: 'Narsipatnam');
        tester.view.physicalSize = const Size(390, 5000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminHomeSectionPage(store: store, part: part))));
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull, reason: part);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Scrolling Text: Marquee is its own scrolling; another animation plays as it appears; scroll speed is saved', (tester) async {
      final store = await _store(settings: const [Entry('scrollingText', {'name': 'Scrolling text', 'speed': 70, 'backgroundColor': '#D32F2F'})]);
      await _show(tester, store, 'scrollingText');
      expect(find.text('(Marquee)'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('preview-box-scrollingText')), matching: find.byType(SectionAnimation)), findsNothing);
      await _pick(tester, _animationDropdown('scrollingText'), 'Typewriter');
      expect(tester.widget<SectionAnimation>(find.descendant(of: find.byKey(const ValueKey('preview-box-scrollingText')), matching: find.byType(SectionAnimation))).type, 'typewriter');
      await tester.enterText(find.byKey(const ValueKey('scroll-speed')), '120');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('save-scrollingText')));
      await tester.tap(find.byKey(const ValueKey('save-scrollingText')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(effectiveSectionConfig(store.entries('settings'), 'scrollingText').text('animation'), 'typewriter');
      final record = store.entries('settings').firstWhere((e) => e.id == 'scrollingText');
      expect(record.number('speed'), 120);
      expect(record.text('backgroundColor'), '#D32F2F', reason: 'what was there stays');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Right Side Ads: the real box changes ad with the chosen animation; the two blocks are saved apart', (tester) async {
      final store = await _store();
      await _show(tester, store, 'ads');
      expect(find.byKey(const ValueKey('editor-boxes')), findsOneWidget, reason: 'the boxes below the ads are on this page too');
      AdSlot slot() => tester.widget<AdSlot>(find.descendant(of: find.byKey(const ValueKey('preview-box-ads')), matching: find.byType(AdSlot)));
      expect(slot().config.animation, 'fade');
      await _pick(tester, _animationDropdown('ads'), 'Flip');
      expect(slot().config.animation, 'flip');
      await tester.ensureVisible(find.byKey(const ValueKey('save-ads')));
      await tester.tap(find.byKey(const ValueKey('save-ads')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(AdsConfig.from(store.entries('settings')).animation, 'flip');
      expect(effectiveSectionConfig(store.entries('settings'), 'boxes').text('animation'), 'fade', reason: 'the boxes below keep their own');
      await _pick(tester, _animationDropdown('boxes'), 'Shake');
      await tester.ensureVisible(find.byKey(const ValueKey('save-boxes')));
      await tester.tap(find.byKey(const ValueKey('save-boxes')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(effectiveSectionConfig(store.entries('settings'), 'boxes').text('animation'), 'shake');
      expect(AdsConfig.from(store.entries('settings')).animation, 'flip');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('buttons lead to the items of each section', (tester) async {
      final store = await _store();
      await _show(tester, store, 'promo');
      expect(find.byKey(const ValueKey('open-promo-items')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-promo-layout')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _show(tester, store, 'ads');
      expect(find.byKey(const ValueKey('open-ads-manage')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-boxes-items')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the customer website', () {
    Future<List<String>> animationsOnHome(WidgetTester tester, Store store) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MarketApp(store: store));
      await tester.pump(const Duration(milliseconds: 800));
      final types = [for (final a in tester.widgetList<SectionAnimation>(find.byType(SectionAnimation))) a.type];
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      return types;
    }

    testWidgets('plays each section start animation: Fade on the offers banner, Slide Up on the offer boxes', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      final types = await animationsOnHome(tester, store);
      expect(types, contains('fade'));
      expect(types, contains('slideUp'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('plays the animation the admin chose for each section', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await store.save('settings', const Entry('animations', {'notice_type': 'bounce', 'promo_type': 'rotate', 'scrollingText_type': 'typewriter'}));
      final types = await animationsOnHome(tester, store);
      expect(types, containsAll(['bounce', 'rotate', 'typewriter']));
      expect(types, isNot(contains('slideUp')));
    });

    testWidgets('None switches a section animation off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await store.save('settings', const Entry('animations', {'notice_type': 'none', 'promo_type': 'none', 'ads_type': 'none', 'boxes_type': 'none', 'scrollingText_type': 'none'}));
      final types = await animationsOnHome(tester, store);
      expect(types, isNot(contains('fade')));
      expect(types, isNot(contains('slideUp')));
    });
  });

  group('the item lists belong to their section', () {
    testWidgets("Today's Offers Box lists only its own boxes and a new one starts as that kind", (tester) async {
      final store = await _store();
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminEntryList(store: store, section: 'promotions', placement: 'carousel'))));
      await tester.pumpAndSettle();
      expect(find.textContaining("Today's Offer"), findsOneWidget);
      expect(find.textContaining('Curated for you'), findsNothing);
      expect(find.textContaining('Big Savings'), findsNothing);
      await tester.pumpWidget(MaterialApp(home: EntryEditor(store: store, collection: 'promotions', initialPlacement: 'box')));
      await tester.pumpAndSettle();
      expect(find.text('box'), findsWidgets, reason: 'a new promotion starts as the kind of the page it was added from');
    });
  });
}
