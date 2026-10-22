import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/ad_reports.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/services/report_export.dart';
import 'package:ecommerce_app/ui/admin_ad_reports.dart';

Entry day(String ad, String d, Map<String, dynamic> data) => Entry('$ad~$d', {'adId': ad, 'day': d, ...data});

final daily = [
  day('a1', '2026-10-24', {
    'views': 10, 'unique': 6, 'taps': 2, 'seconds': 80, 'missed': 3,
    'towns': {'narsipatnam': {'views': 7, 'taps': 2, 'seconds': 60, 'missed': 2}, 'vizag': {'views': 3, 'taps': 0, 'seconds': 20, 'missed': 1}},
    'devices': {'web': {'views': 8, 'taps': 2, 'seconds': 70, 'missed': 3}, 'android': {'views': 2, 'taps': 0, 'seconds': 10, 'missed': 0}},
  }),
  day('a1', '2026-10-26', {
    'views': 4, 'unique': 2, 'taps': 1, 'seconds': 30, 'missed': 0,
    'towns': {'narsipatnam': {'views': 4, 'taps': 1, 'seconds': 30, 'missed': 0}},
    'devices': {'web': {'views': 4, 'taps': 1, 'seconds': 30, 'missed': 0}},
  }),
  day('a2', '2026-10-26', {
    'views': 5, 'unique': 5, 'taps': 0, 'seconds': 25, 'missed': 1,
    'towns': {'vizag': {'views': 5, 'taps': 0, 'seconds': 25, 'missed': 1}},
    'devices': {'android': {'views': 5, 'taps': 0, 'seconds': 25, 'missed': 1}},
  }),
];

void main() {
  group('the report adds up what was stored', () {
    test('totals, per day, per ad, per town and per device', () {
      final r = AdReport.build(daily);
      expect([r.total.views, r.total.unique, r.total.taps, r.total.seconds, r.total.missed], [19, 13, 3, 135, 4]);
      expect(r.total.scheduled, 23);
      expect(r.byDay['2026-10-26']!.views, 9);
      expect(r.byAd['a1']!.views, 14);
      expect(r.byAd['a2']!.views, 5);
      expect(r.byTown['narsipatnam']!.views, 11);
      expect(r.byTown['vizag']!.views, 8);
      expect(r.byDevice['web']!.views, 12);
      expect(r.byDevice['android']!.views, 7);
      expect(r.uniqueKnown, isTrue);
    });

    test('filters by ad, town and device', () {
      expect(AdReport.build(daily, adIds: {'a2'}).total.views, 5);
      final town = AdReport.build(daily, town: 'vizag');
      expect(town.total.views, 8);
      expect(town.total.unique, 0);
      expect(town.uniqueKnown, isFalse, reason: 'unique people is per ad, not per town');
      expect(AdReport.build(daily, device: 'android').total.views, 7);
      expect(AdReport.build(daily, adIds: {'a1'}, town: 'narsipatnam').total.views, 11);
    });

    test('the graph has a column for every day, zeros included', () {
      final days = AdReport.build(daily).days('2026-10-24', '2026-10-27');
      expect(days.map((d) => d.$1), ['2026-10-24', '2026-10-25', '2026-10-26', '2026-10-27']);
      expect(days.map((d) => d.$2.views), [10, 0, 9, 0]);
    });

    test('names and summary', () {
      expect(townLabel('narsipatnam_east'), 'Narsipatnam East');
      final text = reportSummaryText(AdReport.build(daily), from: '2026-10-24', to: '2026-10-27');
      expect(text, contains('Total views: 19'));
      expect(text, contains('Unique people: 13'));
      expect(text, contains('Taps: 3'));
    });
  });

  group('downloads', () {
    final tables = [
      const ReportTable('Per ad', ['Ad', 'Views'], [['Diwali & "Sale"', 14], ['Fresh', 5]]),
      const ReportTable('Per day', ['Day', 'Views'], [['2026-10-26', 9]]),
    ];

    test('the Excel file is a real xlsx with every value', () {
      final bytes = buildXlsx(tables);
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = zip.files.map((f) => f.name).toSet();
      expect(names, containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml']));
      final sheet1 = utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
      expect(sheet1, contains('Diwali &amp; &quot;Sale&quot;'));
      expect(sheet1, contains('<c r="B2"><v>14</v></c>'));
      expect(utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>), contains('name="Per ad"'));
    });

    test('the CSV has a byte-order mark and quotes text', () {
      final bytes = buildCsv(tables.first);
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), '"Ad","Views"\n"Diwali & ""Sale""",14\n"Fresh",5');
    });

    test('the PDF is a PDF', () async {
      final bytes = await buildPdf('Ads report', 'Total views: 19', tables);
      expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(800));
    });
  });

  group('the page', () {
    Future<Store> store() async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.init();
      s.catalog['ads'] = const [
        Entry('a1', {'title': 'Diwali sale', 'shopName': 'Suma', 'order': 1}),
        Entry('a2', {'title': 'Fresh veg', 'shopName': 'Ramu', 'order': 2}),
      ];
      s.catalog['adStatsDaily'] = daily;
      s.catalog['adStats'] = const [
        Entry('a1', {'views': 14, 'unique': 8, 'taps': 3}),
        Entry('a2', {'views': 5, 'unique': 5, 'taps': 0}),
      ];
      return s;
    }

    Future<void> show(WidgetTester tester, Store s) async {
      tester.view.physicalSize = const Size(1300, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: AdminAdReportsPage(store: s, today: DateTime(2026, 10, 27))));
      await tester.pumpAndSettle();
    }

    String card(WidgetTester tester, String key, String label) {
      final column = find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(label));
      expect(column, findsOneWidget, reason: label);
      final texts = find.ancestor(of: column, matching: find.byType(Column)).first;
      return (tester.widget<Text>(find.descendant(of: texts, matching: find.byType(Text)).first)).data!;
    }

    testWidgets('shows the live totals and the totals for the range, matching the stored numbers', (tester) async {
      await show(tester, await store());
      expect(card(tester, 'live-totals', 'Total views, all time (live)'), '19');
      expect(card(tester, 'live-totals', 'Unique people, all time'), '13');
      expect(card(tester, 'range-totals', 'Total views'), '19');
      expect(card(tester, 'range-totals', 'Taps'), '3');
      expect(card(tester, 'range-totals', 'Scheduled but missed'), '4');
      expect(find.byKey(const ValueKey('daily-graph')), findsOneWidget);
    });

    testWidgets('filtering by ad, shop and location changes the numbers', (tester) async {
      final s = await store();
      await show(tester, s);
      Future<void> choose(String key, String text) async {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }

      await choose('report-ad-', 'Fresh veg');
      expect(card(tester, 'range-totals', 'Total views'), '5');
      await choose('report-ad-a2', 'All');
      await choose('report-shop-', 'Suma');
      expect(card(tester, 'range-totals', 'Total views'), '14');
      await choose('report-shop-Suma', 'All');
      await choose('report-town-', 'Vizag');
      expect(card(tester, 'range-totals', 'Total views'), '8');
      expect(find.text('Unique people'), findsNothing, reason: 'hidden while a location is chosen');
    });

    testWidgets('a date range with nothing in it shows zeros, not an error', (tester) async {
      final s = await store();
      s.catalog['adStatsDaily'] = const [];
      await show(tester, s);
      expect(card(tester, 'range-totals', 'Total views'), '0');
      expect(find.text('No numbers in this range.'), findsWidgets);
    });

    testWidgets('the Check views button lists the counted views of an ad', (tester) async {
      final s = await store();
      s.catalog['adViews'] = [
        Entry('v1', {'adId': 'a1', 'type': 'view', 'town': 'Narsipatnam', 'device': 'web', 'at': '2026-10-26T10:00:00'}),
        Entry('v2', {'adId': 'a1', 'type': 'tap', 'town': 'Vizag', 'device': 'android', 'at': '2026-10-26T10:05:00'}),
      ];
      await show(tester, s);
      await tester.tap(find.text('Check views').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('view-log')), findsOneWidget);
      expect(find.text('View · Narsipatnam · Website'), findsOneWidget);
      expect(find.text('Tap · Vizag · App'), findsOneWidget);
      expect(find.text('2026-10-26 10:00:00'), findsOneWidget);
    });
  });
}
