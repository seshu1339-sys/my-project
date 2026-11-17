// The admin command box, part 1 (owner spec A, B, C, I, 17 Nov 2026): the settings registry made from the panel's own lists, the free
// local match (no AI), the command reading (open / count / health / ad / design), the live counts, the field highlight, the risky-step
// confirmation and the agent log. No server and no AI here.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/agent_command.dart';
import 'package:ecommerce_app/domain/agent_counts.dart';
import 'package:ecommerce_app/domain/agent_registry.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/agent_log.dart';
import 'package:ecommerce_app/ui/agent_command_box.dart';
import 'package:ecommerce_app/ui/agent_open.dart';
import 'package:ecommerce_app/ui/agent_registry_build.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final registry = buildAgentRegistry();
  final words = {for (final e in registry) e.id: entryWords(e)};
  String? top(String q, {AgentPlatform? platform}) => rankRegistry(q, registry, platform: platform, wordCache: words).firstOrNull?.entry.id;

  group('registry', () {
    test('every option has one unique ID, a platform, a path, a "what it does" and a deep link', () {
      final ids = [for (final e in registry) e.id];
      expect(ids.toSet().length, ids.length, reason: 'IDs are unique');
      for (final e in registry) {
        expect(e.platforms, isNotEmpty, reason: e.id);
        expect(e.path, isNotEmpty, reason: e.id);
        expect(e.what, isNotEmpty, reason: e.id);
        expect(e.open, isNotEmpty, reason: e.id);
        expect(e.link, startsWith('?open='));
      }
    });

    test('it is made from the panel: pages, form fields, every layout part property, every Android size', () {
      expect(registry.where((e) => e.id == 'page.settings'), hasLength(1));
      expect(registry.where((e) => e.id == 'page.tab.plans'), hasLength(1));
      expect(registry.where((e) => e.id == 'field.settings.postDuration'), hasLength(1));
      expect(registry.where((e) => e.id == 'page.aiprovider'), hasLength(1), reason: 'the new AI page is in it by itself');
      for (final c in layoutComponents.keys) {
        for (final f in allFieldsFor(c)) {
          expect(registry.where((e) => e.id == 'design.web.$c.$f'), hasLength(1), reason: '$c.$f');
        }
      }
      final camera = registry.singleWhere((e) => e.id == 'design.web.search.imageIconSize');
      expect([camera.min, camera.max], [16, 48], reason: 'the safe range comes with it');
      expect(registry.where((e) => e.id.startsWith('design.user.')), isNotEmpty);
      expect(registry.length, greaterThan(1000));
    });

    test('platforms: Android App is not a website page; staff pages are in the Staff app; risky pages are marked', () {
      RegistryEntry e(String id) => registry.singleWhere((x) => x.id == id);
      expect(e('page.androidhome').platforms, {AgentPlatform.user});
      expect(e('page.fieldassistants').platforms, containsAll([AgentPlatform.website, AgentPlatform.staff]));
      expect(e('page.tab.plans').platforms, contains(AgentPlatform.vendor));
      expect(e('page.tab.vendors').risky, isTrue);
      expect(e('page.theme').risky, isFalse);
    });
  });

  group('local match (free, no AI)', () {
    test('names, numbers, Telugu, spelling slips and design words find the right option', () {
      expect(top('post duration'), 'field.settings.postDuration');
      expect(top('5.12'), isNotNull);
      expect(top('scroling text'), 'page.scrollingtext', reason: 'a spelling slip');
      expect(top('ప్లాన్స్'), 'page.tab.plans');
      expect(top("today's offers"), 'page.homeoffers');
      expect(top('search box camera icon color'), 'design.web.search.cameraIconColor');
      expect(top('సెర్చ్ బాక్స్ కెమెరా రంగు'), 'design.web.search.cameraIconColor', reason: 'Telugu words for the same');
      expect(top('qwertyuiop'), isNull);
    });

    test('step 1: a platform keeps the match to its own options', () {
      expect(top('plans', platform: AgentPlatform.staff), isNot('page.tab.plans'));
      expect(top('plans', platform: AgentPlatform.vendor), 'page.tab.plans');
      expect(rankRegistry('ad boxes height', registry, platform: AgentPlatform.user, wordCache: words).map((m) => m.entry.id), contains('design.user.ads.height'));
    });

    test('a clear winner opens at once; a near tie shows the list', () {
      expect(confidentMatch(rankRegistry('ప్లాన్స్', registry, wordCache: words))?.id, 'page.tab.plans');
      expect(confidentMatch(rankRegistry('offers', registry, wordCache: words)), isNull);
      expect(editDistance('scroling', 'scrolling'), 1);
      expect(wordFit('camra', 'camera'), greaterThan(.5));
    });
  });

  group('commands', () {
    const places = ['Narsipatnam', 'Anakapalle', 'Visakhapatnam'];
    test('a number question, in English or Telugu, with the place and the day', () {
      final c = parseAgentCommand('how many vendors added today in Narsipatnam', places: places);
      expect([c.intent, c.metric, c.period, c.place], [AgentIntent.count, AgentMetric.vendorsAdded, AgentPeriod.today, 'Narsipatnam']);
      final te = parseAgentCommand('నిన్న Anakapalle లో ఎన్ని ఐటమ్స్', places: places);
      expect([te.intent, te.metric, te.period, te.place], [AgentIntent.count, AgentMetric.itemsAdded, AgentPeriod.yesterday, 'Anakapalle']);
      expect(parseAgentCommand('how many vendors are waiting for approval').metric, AgentMetric.vendorsWaiting);
    });

    test('what is not working, in English and Telugu', () {
      expect(parseAgentCommand('what is not working?').intent, AgentIntent.health);
      expect(parseAgentCommand('ఏం పని చేయట్లేదు').intent, AgentIntent.health);
    });

    test('an ad by command: place, km, days, where it shows, and the wide reaches', () {
      final c = parseAgentCommand("this photo, Today's Offers, Narsipatnam, 10 km, 2 days", places: places);
      expect([c.intent, c.place, c.km, c.days, c.reach, c.placement], [AgentIntent.ad, 'Narsipatnam', 10.0, 2, AdReach.radius, 'todaysOffers']);
      expect(parseAgentCommand("Today's Offers ad All India 3 days").reach, AdReach.allIndia);
      expect(parseAgentCommand('right side ad Visakhapatnam district 1 day', places: places).placement, 'rightBox');
      expect(parseAgentCommand('right side ad Visakhapatnam district 1 day', places: places).reach, AdReach.district);
      expect(parseAgentCommand('show this live rate in Narsipatnam', places: places).intent, AgentIntent.rate);
    });

    test('a design change, with the value when one is said', () {
      final w = parseAgentCommand('make the search box wider by 20');
      expect([w.intent, w.value], [AgentIntent.design, '20']);
      expect(parseAgentCommand("Today's Offers రంగు ఎరుపు").value, 'ఎరుపు');
      expect(parseAgentCommand('search box color #ff0000').value, '#ff0000');
      expect(parseAgentCommand('ప్లాన్స్ తెరువు').intent, AgentIntent.open);
    });
  });

  group('live counts', () {
    test('the day documents add up, for one town or all', () {
      final docs = [
        {'total': 5, 'keys': {'a': {'key': 'Narsipatnam', 'label': 'Narsipatnam', 'town': 'Narsipatnam', 'count': 3}, 'b': {'key': 'Tuni', 'town': 'Tuni', 'count': 2}}},
        {'total': 1, 'keys': {'c': {'key': 'x', 'label': 'Krishna Bazar (Narsipatnam)', 'town': '', 'count': 1}}},
      ];
      expect(sumUsage(docs, ''), 6);
      expect(sumUsage(docs, 'narsipatnam'), 4);
      expect(periodDays(AgentPeriod.week, DateTime.utc(2026, 11, 17, 20)), hasLength(7));
      expect(periodDays(AgentPeriod.today, DateTime.utc(2026, 11, 17, 20)).single, '2026-11-18', reason: 'the Indian day');
      final answer = countAnswer(parseAgentCommand('how many vendors today in Narsipatnam', places: const ['Narsipatnam']), 3);
      expect(answer, contains('3 vendors registered in Narsipatnam today'));
      expect(answer, contains('ఈరోజు 3'));
    });
  });

  group('the command box', () {
    late Store store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = Store();
      await store.init();
      AgentLog.testSink = [];
    });
    tearDown(() {
      AgentLog.testSink = null;
      store.dispose();
    });

    testWidgets('a clear name opens at once and is logged; a number question is answered without AI; the platform filters', (tester) async {
      final opened = <String>[];
      final asked = <AgentCommand>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminSettingsSearchBar(
        store: store,
        open: (e) => opened.add(e.id),
        count: (c) async { asked.add(c); return '3 vendors registered today.'; },
      ))));
      await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'post duration');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(opened, ['field.settings.postDuration']);
      expect(AgentLog.testSink!.single['action'], 'open');

      await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'how many vendors today');
      await tester.pump();
      expect(find.byKey(const ValueKey('agent-intent')), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(asked.single.metric, AgentMetric.vendorsAdded);
      expect(find.text('3 vendors registered today.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('agent-platform')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agent-platform-staff')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'offers');
      await tester.pump();
      expect(find.textContaining('Staff app'), findsWidgets, reason: 'only Staff app options are listed');
    });

    testWidgets('the menu keeps the AI assistant and the older AI Agent', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminSettingsSearchBar(store: store))));
      await tester.tap(find.byKey(const ValueKey('agent-menu')));
      await tester.pumpAndSettle();
      expect(find.text('AI assistant (questions)'), findsOneWidget);
      expect(find.text('Older AI Agent'), findsOneWidget);
      expect(find.text('AI provider & usage'), findsOneWidget);
      expect(find.text('Agent log'), findsOneWidget);
    });

    testWidgets('an option opens at its field, which is highlighted', (tester) async {
      store.catalog['settings'] = [...store.entries('settings').where((e) => e.id != 'business'), const Entry('business', {'name': 'Local Market'})];
      final entry = registry.singleWhere((e) => e.id == 'field.settings.postDuration');
      await tester.pumpWidget(MaterialApp(home: agentPageFor(store, entry)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('agent-focus-postDuration')), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('a risky step needs YES typed', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
        onPressed: () async => result = await confirmRiskyAction(context, title: 'Suspend vendor?', detail: 'The shop goes off line.'),
        child: const Text('go'),
      ))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('agent-risky-ok'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('agent-risky-yes')), 'అవును');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-risky-ok')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });
}
