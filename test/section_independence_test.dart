import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/admin_ads.dart';
import 'package:ecommerce_app/ui/animation_settings.dart';
import 'package:ecommerce_app/ui/animation_settings_form.dart';
import 'package:ecommerce_app/ui/home_ticker_section.dart';
import 'package:ecommerce_app/ui/notice_independence.dart';
import 'package:ecommerce_app/ui/vendor_section_kit.dart';
import 'package:ecommerce_app/ui/vendor_section_requests.dart';

Future<Store> _store(List<Entry> settings) async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  store.catalog['settings'] = [...settings];
  return store;
}

const _scrolling = Entry('scrollingText', {'name': 'Scrolling text', 'text': 'hello gayatri how are u', 'borderColor': '#E0A400', 'opacity': 1, 'textColor': '#EAB308'});

void main() {
  group("Today's Offers is independent of the Scrolling Text", () {
    test('it lists what the banner inherits: only what its own record lacks', () {
      final inherited = noticeInherited(_scrolling, const Entry('section_notice', {'textColor': '#FFFFFF', 'section': 'notice'}));
      expect(inherited.keys.toSet(), {'text', 'borderColor', 'opacity'}, reason: 'its own textColor wins; unrelated keys such as name are not copied');
      expect(noticeInherited(null, null), isEmpty);
    });

    test('making it independent copies those values, marks it, and changes nothing else', () async {
      final store = await _store([_scrolling, const Entry('section_notice', {'section': 'notice', 'fontSize': '35'})]);
      expect(noticeIsIndependent(store.entries('settings')), isFalse);
      expect(await makeNoticeIndependent(store), 4, reason: 'text, border colour, opacity and text colour');
      final own = store.entries('settings').firstWhere((e) => e.id == 'section_notice');
      expect(own.text('text'), 'hello gayatri how are u');
      expect(own.text('borderColor'), '#E0A400');
      expect(own.text('fontSize'), '35', reason: 'what it had stays');
      expect(noticeIsIndependent(store.entries('settings')), isTrue);
      expect(await makeNoticeIndependent(store), 0, reason: 'done once');
      // the Scrolling Text itself is untouched
      expect(store.entries('settings').firstWhere((e) => e.id == 'scrollingText').data, _scrolling.data);
    });

    testWidgets('until then it still follows the Scrolling Text; afterwards it does not', (tester) async {
      Future<String> banner(Store store) async {
        tester.view.physicalSize = const Size(1200, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: store,
              builder: (context, _) => HomeTickerSection(
                store: store,
                settings: store.entries('settings'),
                promotions: const [],
                products: const [Entry('p1', {'name': 'Apple', 'price': 25, 'compareAtPrice': 30})],
                onProduct: (_) {},
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(seconds: 1));
        final label = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').firstWhere((t) => t.isNotEmpty && !t.contains('Apple'), orElse: () => '');
        await tester.pumpWidget(const SizedBox());
        return label;
      }

      final store = await _store([_scrolling]);
      expect(await banner(store), 'hello gayatri how are u', reason: 'the old behaviour: the label comes from the Scrolling Text');
      await store.save('settings', const Entry('scrollingText', {'name': 'Scrolling text', 'text': 'Changed on the Scrolling Text'}));
      expect(await banner(store), 'Changed on the Scrolling Text', reason: 'not independent yet');

      await makeNoticeIndependent(store);
      expect(await banner(store), 'Changed on the Scrolling Text', reason: 'it kept what it showed');
      await store.save('settings', const Entry('scrollingText', {'name': 'Scrolling text', 'text': 'Changed AGAIN'}));
      expect(await banner(store), 'Changed on the Scrolling Text', reason: 'now the Scrolling Text no longer reaches it');
    });
  });

  group('a settings page never undoes what another page saved in the same record', () {
    testWidgets('Animations: a choice made meanwhile on another page survives saving here', (tester) async {
      final store = await _store([const Entry('animations', {'name': 'Animations', 'promo_type': 'zoom'})]);
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAnimationsForm(store: store))));
      await tester.pumpAndSettle();
      // meanwhile, on the Today's Offers page
      await store.updateFields('settings', 'animations', {'notice_type': 'bounce', 'promo_type': 'rotate'});
      // here: change something else and save
      await tester.tap(find.byKey(const ValueKey('anim-global-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('anim-global-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('anim-header-enabled')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('anim-save')));
      await tester.tap(find.byKey(const ValueKey('anim-save')));
      await tester.pumpAndSettle();
      final saved = store.entries('settings').firstWhere((e) => e.id == 'animations');
      expect(saved.text('header_enabled'), 'false', reason: 'what was changed here is saved');
      expect(saved.text('notice_type'), 'bounce', reason: 'the other page choice is still there');
      expect(saved.text('promo_type'), 'rotate', reason: 'and not reverted to what this page loaded');
    });

    testWidgets('Ads settings: the animation chosen on the Right Side Ads page survives saving the common settings', (tester) async {
      final store = await _store([const Entry('adsConfig', {'name': 'Ads settings', 'radius': 12})]);
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AdsConfigForm(store: store)))));
      await tester.pumpAndSettle();
      await store.updateFields('settings', 'adsConfig', {'animation': 'flip', 'animationSpeed': 9});
      await tester.enterText(find.byKey(const ValueKey('ads-config-gap-null')), '20');
      await tester.ensureVisible(find.byKey(const ValueKey('ads-config-save')));
      await tester.tap(find.byKey(const ValueKey('ads-config-save')));
      await tester.pumpAndSettle();
      final config = AdsConfig.from(store.entries('settings'));
      expect(config.gap, 20);
      expect(config.animation, 'flip', reason: 'set meanwhile on the other page');
      expect(config.animationSpeed, 9);
      expect(config.radius, 12);
    });

    test('each part keeps its own animation: changing one never touches another', () {
      final a = [const Entry('animations', {'promo_type': 'zoom'})];
      final b = [const Entry('animations', {'promo_type': 'zoom', 'notice_type': 'bounce'})];
      expect(effectiveSectionConfig(a, 'promo').text('animation'), effectiveSectionConfig(b, 'promo').text('animation'));
      expect(effectiveSectionConfig(a, 'ads').text('animation'), effectiveSectionConfig(b, 'ads').text('animation'));
      expect(effectiveSectionConfig(a, 'notice').text('animation'), 'fade');
      expect(effectiveSectionConfig(b, 'notice').text('animation'), 'bounce');
    });
  });

  group('vendor sections', () {
    testWidgets('each keeps its own busy flag: one working never greys out another', (tester) async {
      final release = Completer<void>();
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [_Probe(key: ValueKey('a')), _Probe(key: ValueKey('b'))]))));
      _ProbeState state(String k) => tester.state<_ProbeState>(find.byKey(ValueKey(k)));
      unawaited(state('a').run(() => release.future));
      await tester.pump();
      expect(state('a').busy, isTrue);
      expect(state('b').busy, isFalse);
      release.complete();
      await tester.pump();
      expect(state('a').busy, isFalse);
    });

    testWidgets('an error in one section is shown as a message and leaves the others working', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [_Probe(key: ValueKey('a')), _Probe(key: ValueKey('b'))]))));
      final a = tester.state<_ProbeState>(find.byKey(const ValueKey('a')));
      await a.run(() async => throw StateError('boom'));
      await tester.pump();
      expect(find.text('Bad state: boom'), findsOneWidget);
      expect(a.busy, isFalse);
      expect(tester.state<_ProbeState>(find.byKey(const ValueKey('b'))).busy, isFalse);
    });

    testWidgets('the change request and the verified-purchase sections stand alone (their own boxes, no shared state)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = Store();
      await store.init();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [VendorChangeRequestSection(store: store, uid: 'v1'), VendorVerifyPurchaseSection(store: store)]))));
      await tester.enterText(find.widgetWithText(TextField, 'Product or shop ID'), 'p1');
      await tester.enterText(find.widgetWithText(TextField, 'Order ID'), 'o1');
      expect(find.text('p1'), findsOneWidget);
      expect(find.text('o1'), findsOneWidget);
      // removing one section leaves the other as it was
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [VendorVerifyPurchaseSection(store: store)]))));
      expect(find.text('Verified purchase'), findsOneWidget);
      expect(find.text('Submit a product or shop change'), findsNothing);
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with VendorSectionState {
  @override
  Widget build(BuildContext context) => Text(busy ? 'busy' : 'idle');
}
