// Owner round of 13 Nov 2026: the hidden day choices with the post duration note, the admin's settings search (name or number, typed
// or spoken), vendor and staff app ads only where they were posted, the voice search language, and the admin AI assistant page.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/domain/ads.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/domain/post_duration.dart';
import 'package:ecommerce_app/modules/premiumscreen/offer_form_dialog.dart';
import 'package:ecommerce_app/services/search_providers.dart';
import 'package:ecommerce_app/ui/admin_ai_assistant.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';
import 'package:ecommerce_app/ui/admin_settings_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = Store();
  await store.init();
  return store;
}

void main() {
  test('the vendor is told the admin\'s duration before posting, and the day choices are hidden by default', () {
    expect(showPostDayChoices, isFalse);
    expect(postDurationNotice(const Entry('business', {})), startsWith('Every post shows for 24 hours after you post it'));
    expect(postDurationNotice(const Entry('business', {'postDuration': '7d'})), contains('7 days'));
    expect(postDurationNotice(const Entry('business', {'postDuration': '1m'})), contains('30 days'));
    expect(postDurationNotice(const Entry('business', {})), contains('Paid plans give more photos and posts, not a longer time'));
  });

  testWidgets("Today's Offers form: no day chips, the note shows, the longest choice is sent (the server caps it)", (tester) async {
    OfferFormResult? sent;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async => sent = await showDialog<OfferFormResult>(context: context, builder: (_) => const OfferFormDialog(
        items: [OfferItemChoice(id: 'p1', name: 'Rice', photoUrl: 'https://example.com/1.jpg')],
        dayOptions: {7: '1 week', 30: '1 month', 90: '3 months'},
        durationNote: 'Every post shows for 24 hours after you post it.',
      )),
      child: const Text('open'),
    )))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todays-offer-duration-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('todays-offer-days-7')), findsNothing, reason: 'the choices stay in the code but are hidden');
    await tester.tap(find.byKey(const ValueKey('todays-offer-item-p1')));
    await tester.enterText(find.byKey(const ValueKey('todays-offer-price')), '45');
    await tester.tap(find.byKey(const ValueKey('todays-offer-send')));
    await tester.pumpAndSettle();
    expect(sent?.days, 90);
  });

  test('the settings index numbers every section and the fields of the one-form sections; search finds by name or number', () {
    final index = adminSettingsIndex();
    final business = index.firstWhere((h) => h.sectionKey == 'settings' && !h.isField);
    expect(business.serial, '5');
    final duration = index.firstWhere((h) => h.hint == 'postDuration');
    expect(duration.serial, startsWith('5.'));
    expect(duration.label, startsWith('Business Profile › Post duration'));
    expect(searchAdminSettings(duration.serial, index: index).single.hint, 'postDuration');
    expect(searchAdminSettings('5', index: index).first.title, 'Business Profile', reason: 'a section number brings the section, then its fields');
    expect(searchAdminSettings('number 5', index: index).first.title, 'Business Profile', reason: 'a spoken "number five" works too');
    expect(searchAdminSettings('post duration', index: index).map((h) => h.hint), contains('postDuration'));
    expect(searchAdminSettings('SCROLLING', index: index).first.title, 'Scrolling Text');
    expect(searchAdminSettings('area names', index: index).first.sectionKey, 'areaNames');
    expect(searchAdminSettings('nothing like this', index: index), isEmpty);
    expect(index.where((h) => !h.isField).last.sectionKey, 'aiAssistant', reason: 'the new section comes last, so the old numbers stay');
  });

  testWidgets('the admin types or says a setting and a tap opens it', (tester) async {
    final store = await _store();
    AdminSettingHit? opened;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminSettingsSearchBar(store: store, listen: () async => 'scrolling text', open: (h) => opened = h))));
    await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'post duration');
    await tester.pump();
    final hit = searchAdminSettings('post duration').first;
    await tester.tap(find.byKey(ValueKey('admin-settings-hit-${hit.serial}')));
    expect(opened?.hint, 'postDuration');
    await tester.tap(find.byKey(const ValueKey('admin-settings-search-mic')));
    await tester.pumpAndSettle();
    expect(find.text('Scrolling Text'), findsWidgets, reason: 'what was said is searched');
    await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'zzz');
    await tester.pump();
    expect(find.byKey(const ValueKey('admin-settings-search-none')), findsOneWidget);
    store.dispose();
  });

  test('vendor and staff app ads posted for a place show only within the km; ads with no place show to all', () {
    final now = DateTime(2026, 11, 13, 10);
    final ads = [
      const Entry('everyone', {'title': 'a', 'audience': 'vendors'}),
      const Entry('kpl', {'title': 'b', 'audience': 'vendors', 'shopId': 'kpl'}),
      const Entry('far', {'title': 'c', 'audience': 'vendors', 'shopId': 'nrp'}),
    ];
    bool near(Entry ad) => ad.text('shopId') == 'kpl';
    expect([for (final a in appAds(ads, now, reaches: near)) a.id], ['everyone', 'kpl']);
    expect([for (final a in appAds(ads, now, staff: true, reaches: near)) a.id], ['everyone', 'kpl']);
    expect([for (final a in appAds(ads, now)) a.id], ['everyone'], reason: 'no place known: none of the placed ads');
  });

  test('voice search listens in Telugu or English (India), falling back where the phone has no Telugu', () {
    expect(voiceLocaleFor('te'), 'te_IN');
    expect(voiceLocaleFor('en'), 'en_IN');
    expect(voiceLocaleFor('hi'), 'en_IN');
    expect(pickVoiceLocale('te_IN', ['en_IN', 'te-IN']), 'te-IN');
    expect(pickVoiceLocale('te_IN', ['en_IN', 'hi_IN']), 'en_IN');
    expect(pickVoiceLocale('te_IN', ['en_US']), isNull, reason: 'then the device language');
    expect(pickVoiceLocale('te_IN', const []), 'te_IN', reason: 'a browser that lists no locales gets the asked one');
  });

  testWidgets('the AI assistant page sends the question (typed or spoken) and shows the answer or the limit message', (tester) async {
    final store = await _store();
    final asked = <String>[];
    var limit = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminAiAssistantPage(
      store: store,
      ask: (q) async {
        asked.add(q);
        if (limit) throw StateError("You have used today's 50 questions. Please try again tomorrow.");
        return '2 vendors are waiting.';
      },
      listen: () async => 'ఎంత మంది vendors waiting?',
    ))));
    await tester.enterText(find.byKey(const ValueKey('ai-assistant-question')), 'How many vendors are waiting?');
    await tester.tap(find.byKey(const ValueKey('ai-assistant-ask')));
    await tester.pumpAndSettle();
    expect(find.text('2 vendors are waiting.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-assistant-mic')));
    await tester.pumpAndSettle();
    expect(asked.last, 'ఎంత మంది vendors waiting?');
    limit = true;
    await tester.enterText(find.byKey(const ValueKey('ai-assistant-question')), 'And now?');
    await tester.tap(find.byKey(const ValueKey('ai-assistant-ask')));
    await tester.pumpAndSettle();
    expect(find.textContaining('try again tomorrow'), findsOneWidget);
    store.dispose();
  });
}
