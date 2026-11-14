import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/admin_routes.dart';
import 'package:ecommerce_app/ui/admin_settings.dart';
import 'package:ecommerce_app/ui/admin_settings_search.dart';
import 'package:ecommerce_app/ui/ai_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The admin route map (owner, 14 Nov 2026): one list of pages with Telugu names, used by the search box, the voice search and the AI
// agent's "open ..." commands.
void main() {
  final index = adminSettingsIndex();
  final pages = [for (final h in index) if (!h.isField) h];

  test('every page of the admin panel has a line in the route map (a Telugu name), and every line names a real page', () {
    final missing = [for (final h in pages) if (h.aliases.trim().isEmpty) '${h.sectionKey} (${h.title})'];
    expect(missing, isEmpty, reason: 'add these to lib/ui/admin_routes.dart');
    final keys = {for (final h in pages) h.sectionKey};
    expect([for (final r in adminRoutes) if (!keys.contains(r.key)) r.key], isEmpty);
  });

  test('typed or said in English or Telugu, with or without "open", the right page is found', () {
    String? key(String text) => bestAdminPage(text, index: index)?.sectionKey;
    expect(key('Cells'), 'tab:Staff Areas');
    expect(key('సెల్స్ తెరువు'), 'tab:Staff Areas');
    expect(key('Cells తెరువు'), 'tab:Staff Areas');
    expect(key('Plans చూపించు'), 'tab:Plans');
    expect(key('ప్లాన్స్'), 'tab:Plans');
    expect(key('show plans'), 'tab:Plans');
    expect(key("Today's Offer"), 'homeOffers');
    expect(key('open staff areas'), 'tab:Staff Areas');
    expect(key('వెండర్లు'), 'tab:Vendors');
    expect(key('qwertyuiop'), isNull);
    expect(adminCommandQuery('Cells తెరువు'), 'cells');
    expect(adminAsksToOpen('ప్లాన్స్ చూపించు'), isTrue);
    expect(adminAsksToOpen('how many vendors'), isFalse);
  });

  testWidgets('search box: Telugu names give suggestions, Enter opens the page, and the mic opens it at once', (tester) async {
    final opened = <String>[];
    var said = 'సెల్స్ తెరువు';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AdminSettingsSearchBar(store: Store(), open: (hit) => opened.add(hit.sectionKey), listen: () async => said)),
    ));
    await tester.enterText(find.byKey(const ValueKey('admin-settings-search')), 'ప్లాన్స్');
    await tester.pump();
    expect(find.text('Plans'), findsWidgets);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(opened, ['tab:Plans']);
    await tester.tap(find.byKey(const ValueKey('admin-settings-search-mic')));
    await tester.pumpAndSettle();
    expect(opened.last, 'tab:Staff Areas', reason: 'voice: one page named, opened at once');
    said = 'offers';
    await tester.tap(find.byKey(const ValueKey('admin-settings-search-mic')));
    await tester.pumpAndSettle();
    expect(opened.length, 2, reason: 'several pages fit: the list shows, nothing opens by itself');
  });

  testWidgets('AI agent: "Cells తెరువు" opens the page in the app, with no server call', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiAgentChat(store: Store(), voiceEnabled: false, openPage: opened.add))));
    await tester.enterText(find.byType(TextField).first, 'Cells తెరువు');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    if (opened.isEmpty) {
      await tester.tap(find.byIcon(Icons.send).first);
      await tester.pumpAndSettle();
    }
    expect(opened, ['tab:Staff Areas']);
    expect(find.text('Opening Cells'), findsOneWidget);
  });
}
