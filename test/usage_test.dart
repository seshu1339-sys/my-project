import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/usage.dart';
import 'package:ecommerce_app/services/usage_buttons.dart';
import 'package:ecommerce_app/ui/contact_actions.dart';
import 'package:ecommerce_app/ui/screen_view.dart';
import 'package:ecommerce_app/ui/search_usage_reporter.dart';

void main() {
  late List<Map<String, Object?>> sent;
  setUp(() {
    sent = [];
    Usage.instance = Usage(app: 'customer', deviceId: 'device-0123456789abcdef', platform: 'web', transport: (b) async => sent.add(b), flushEvery: const Duration(hours: 1));
  });
  tearDown(() {
    Usage.instance?.dispose();
    Usage.instance = null;
    Usage.sinks.clear();
  });

  List<Map<String, Object?>> events() => [for (final b in sent) ...(b['events'] as List).cast<Map<String, Object?>>()];

  test('events wait in a queue and go in batches of 50; the first batch says the account is active', () async {
    for (var i = 0; i < 60; i++) {
      Usage.track('search', key: 'q$i');
    }
    Usage.track('shop_call', key: 'shopA', label: 'Lakshmi Kirana', town: 'Narsipatnam');
    expect(Usage.instance!.pending, 61);
    await Usage.instance!.flush();
    expect(sent.length, 2);
    expect((sent[0]['events'] as List).length, 50);
    expect(sent[0]['touch'], isTrue);
    expect(sent[1]['touch'], isFalse);
    expect(events().last, {'event': 'shop_call', 'key': 'shopA', 'label': 'Lakshmi Kirana', 'town': 'Narsipatnam'});
    // nothing waiting and recently active: nothing is sent
    sent.clear();
    await Usage.instance!.flush();
    expect(sent, isEmpty);
  });

  test('without a tracker (demo, tests) counting does nothing; other listeners still hear every event', () {
    final heard = <String>[];
    Usage.sinks.add((event, params) => heard.add('$event ${params['key']}'));
    Usage.instance = null;
    Usage.track('transport_click', key: 'transport');
    Usage.button('header_cart');
    expect(heard, ['transport_click transport', 'button header_cart']);
  });

  test('every counted screen and button is listed once for the admin', () {
    final ids = usageItems.map((i) => '${i.kind}:${i.id}').toList();
    expect(ids.toSet().length, ids.length);
    expect(usageItems.every((i) => ['customer', 'vendor', 'staff', 'admin'].contains(i.app)), isTrue);
  });

  testWidgets('a screen counts once when it opens; calls and WhatsApp are told to the caller', (tester) async {
    final ways = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ScreenView('shop', child: Scaffold(body: ContactActions(phone: '9876511111', onUsed: ways.add))),
    ));
    await tester.pump();
    expect(events().isEmpty && Usage.instance!.pending == 1, isTrue);
    await tester.tap(find.text('Call'));
    await tester.tap(find.text('WhatsApp'));
    expect(ways, ['call', 'whatsapp']);
    trackShopContact('call', const Entry('shopA', {'name': 'Lakshmi Kirana', 'town': 'Narsipatnam'}));
    trackShopContact('email', const Entry('shopA', {}));
    await Usage.instance!.flush();
    expect(events().map((e) => '${e['event']}:${e['key']}'), ['screen_view:shop', 'shop_call:shopA']);
  });

  testWidgets('what customers search for is counted once they stop typing, and a search that finds nothing too', (tester) async {
    Widget reporter(String q, int results) => MaterialApp(home: SearchUsageReporter(query: q, results: results, town: 'Narsipatnam'));
    await tester.pumpWidget(reporter('dra', 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(reporter('dragon fruit', 0));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpWidget(reporter('Dragon  fruit ', 0)); // the same search again
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpWidget(reporter('tomato', 4));
    await tester.pump(const Duration(milliseconds: 1600));
    await Usage.instance!.flush();
    expect(events().map((e) => '${e['event']}:${e['key']}'), ['search:dragon fruit', 'search_no_result:dragon fruit', 'search:tomato']);
  });
}
