// Design changes by command, part 5 (owner spec E, 17 Nov 2026): the value from the words (colour names, "wider by 20", "20%"), the safe
// range (auto-fit) and the warnings, the preview before saving, saving only on OK with a history line, and one-click undo. No server.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/agent_command.dart';
import 'package:ecommerce_app/domain/agent_registry.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/design_change.dart';
import 'package:ecommerce_app/services/agent_log.dart';
import 'package:ecommerce_app/ui/agent_design_flow.dart';
import 'package:ecommerce_app/ui/agent_registry_build.dart';
import 'package:ecommerce_app/ui/shared.dart' show priceOrNotUpdated, noPriceText;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final registry = buildAgentRegistry();
  RegistryEntry e(String id) => registry.singleWhere((x) => x.id == id);

  test('every value that was fixed in the code is a design option now, with its safe range', () {
    final height = e('design.web.design.rightBoxHeight');
    expect([height.min, height.max], [120, 400]);
    expect(designTargetOf(height), (record: 'design', field: 'rightBoxHeight'));
    expect(designTargetOf(e('design.web.search.cameraIconColor')), (record: 'section_search', field: 'cameraIconColor'));
    expect(designTargetOf(e('design.user.search.height')), (record: 'androidSizes', field: 'search__height'));
    expect(registry.where((x) => x.id == 'design.web.design.todaysOfferLabel'), hasLength(1));
  });

  test('the "no price" words are a setting: default until the admin sets them, then everywhere', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await store.init();
    expect(priceOrNotUpdated(0, store), 'Local vendor not updated item price');
    expect(registry.where((x) => x.id == 'design.web.design.noPriceText'), hasLength(1), reason: 'the command box finds it');
    store.catalog['settings'] = [...store.entries('settings'), const Entry('design', {'noPriceText': 'ధర త్వరలో'})];
    expect(priceOrNotUpdated(0, store), 'ధర త్వరలో');
    expect(noPriceText(store), 'ధర త్వరలో');
    expect(priceOrNotUpdated(40, store), isNot('ధర త్వరలో'));
    store.dispose();
  });

  test('the value from the words: colours, absolute, wider / smaller by, percent', () {
    expect(proposedValue(DesignValueKind.color, 'red', null), '#FFD32F2F');
    expect(proposedValue(DesignValueKind.color, 'ఎరుపు', null), '#FFD32F2F');
    expect(proposedValue(DesignValueKind.color, '#00ff00', null), '#FF00FF00');
    expect(proposedValue(DesignValueKind.number, '30', 24, text: 'camera icon size 30'), '30');
    expect(proposedValue(DesignValueKind.number, '20', 600, text: 'make the search box wider by 20'), '620');
    expect(proposedValue(DesignValueKind.number, '10%', 200, text: 'ad boxes 10% smaller'), '180');
    expect(proposedValue(DesignValueKind.number, '', 50, text: 'make it bigger'), '55');
    expect(proposedValue(DesignValueKind.text, '', null, text: 'change the heading text to "Best offers today"'), 'Best offers today');
  });

  test('auto-fit into the safe range, with the warnings the admin sees', () {
    final icon = e('design.web.search.imageIconSize');
    final big = fitDesignValue(icon, DesignValueKind.number, '90', current: 24);
    expect(big.value, '48');
    expect(big.warnings.single, contains('safe maximum 48'));
    final width = e('design.web.search.width');
    final wide = fitDesignValue(width, DesignValueKind.number, '1500', current: 0);
    expect(wide.warnings.join(' '), contains('most screens'));
    expect(wide.warnings.join(' '), contains('automatic'));
    expect(fitDesignValue(e('design.web.search.cameraIconColor'), DesignValueKind.color, 'zz').warnings.single, contains('Choose a colour'));
    expect(describeChange(icon, 24, '30'), contains('24 → 30'));
  });

  group('the page', () {
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

    testWidgets('asks with the range, previews, saves only on OK, writes the history, and Undo puts it back', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store.catalog['settings'] = [...store.entries('settings').where((x) => x.id != 'section_search'), const Entry('section_search', {'imageIconSize': 24})];
      final history = <Map<String, Object?>>[];
      final command = parseAgentCommand('search box camera icon size 30');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => DesignChangePage(store: store, entry: e('design.web.search.imageIconSize'), command: command, saveHistory: (r) async => history.add(r))))));
      expect(find.text('How much? Safe range 16 to 48.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('design-value'))).controller!.text, '30');
      await tester.tap(find.byKey(const ValueKey('design-preview-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('design-preview')), findsOneWidget);
      expect(find.textContaining('24 → 30'), findsWidgets);
      expect(store.entries('settings').firstWhere((x) => x.id == 'section_search').data['imageIconSize'], 24, reason: 'nothing saved before OK');
      await tester.tap(find.byKey(const ValueKey('design-ok')));
      await tester.pumpAndSettle();
      expect(store.entries('settings').firstWhere((x) => x.id == 'section_search').data['imageIconSize'], 30);
      expect(history.single['before'], 24);
      expect(history.single['after'], 30);
      expect(find.byKey(const ValueKey('design-done')), findsOneWidget);
      expect(AgentLog.testSink!.last['action'], 'design_change');
      await undoDesign(store, 'section_search', 'imageIconSize', 24);
      expect(store.entries('settings').firstWhere((x) => x.id == 'section_search').data['imageIconSize'], 24);
    });
  });
}
