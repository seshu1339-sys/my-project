import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/modules/flash/admin_flash_answers.dart';
import 'package:ecommerce_app/modules/flash/flash_answers.dart';
import 'package:ecommerce_app/ui/health_extras.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Cost cuts part 4 (18 Nov 2026): ready-question buttons with stored answers (no AI), edited by the admin, counted for Health.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the starting answers in the app are the server\'s file, in English and Telugu, for every chat', () async {
    final all = await defaultFlashAnswers();
    expect(all.length, greaterThanOrEqualTo(15));
    for (final kind in ['user', 'vendor', 'premium', 'provider', 'staff']) {
      expect(readyFor(kind, all), isNotEmpty, reason: kind);
      expect(readyFor(kind, all).map((a) => a.id), contains('login'));
    }
    final vendor = readyFor('vendor', all).map((a) => a.id).toList();
    expect(vendor.take(3), ['plans', 'prices', 'validity'], reason: "the owner's order: Plans, Prices, Validity");
    final plans = all.firstWhere((a) => a.id == 'plans');
    expect(plans.question('te'), 'ప్లాన్లు');
    expect(plans.answer('en'), startsWith('Free plan: 2 items'));
    expect(plans.answer('hi'), plans.answerEn, reason: 'other languages read English');
  });

  test('switched-off answers and other chats\' answers are not shown; the admin order holds', () {
    final list = flashAnswersFrom([
      {'id': 'b', 'chats': ['user'], 'order': 2, 'question': {'en': 'B'}, 'answer': {'en': 'b'}},
      {'id': 'a', 'chats': ['user'], 'order': 1, 'question': {'en': 'A'}, 'answer': {'en': 'a'}},
      {'id': 'off', 'chats': ['user'], 'active': false, 'question': {'en': 'Off'}, 'answer': {'en': 'x'}},
      {'id': 'v', 'chats': ['vendor'], 'question': {'en': 'V'}, 'answer': {'en': 'v'}},
    ]);
    expect(readyFor('user', list).map((a) => a.id), ['a', 'b']);
  });

  testWidgets('a tap shows the stored answer at once (no waiting) and is counted', (tester) async {
    final all = await tester.runAsync(defaultFlashAnswers);
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: FlashReadyAnswers(answers: readyFor('vendor', all!), language: 'te', onTap: (a) => tapped.add(a.id)))),
    ));
    expect(find.text('ప్లాన్లు'), findsOneWidget, reason: 'Telugu buttons for a Telugu app');
    await tester.tap(find.byKey(const ValueKey('flash-ready-validity')));
    await tester.pump();
    expect(find.byKey(const ValueKey('flash-ready-answer-validity')), findsOneWidget);
    expect(find.textContaining('పెయిడ్ ప్లాన్'), findsOneWidget);
    expect(tapped, ['validity']);
  });

  testWidgets('the admin edits, adds, switches off and removes answers, and saves the whole list', (tester) async {
    tester.view.physicalSize = const Size(1400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final start = [
      const FlashAnswer(id: 'plans', chats: ['vendor'], questionEn: 'Plans', answerEn: 'Old words', keywords: ['plan']),
      const FlashAnswer(id: 'login', chats: ['user', 'vendor'], questionEn: 'Login problem', answerEn: 'Use Google'),
    ];
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AdminFlashAnswers(answers: start, starting: () async => start, onSave: (d) async => saved = d)),
    ));
    await tester.enterText(find.byKey(const ValueKey('flash-answer-a-en-plans')), 'New words');
    await tester.enterText(find.byKey(const ValueKey('flash-answer-k-plans')), 'plan, ప్లాన్, plannu');
    await tester.tap(find.byKey(const ValueKey('flash-answer-on-login')));
    await tester.tap(find.byKey(const ValueKey('flash-answer-add')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('flash-answer-q-en-answer_3')), 'Shop hours');
    await tester.enterText(find.byKey(const ValueKey('flash-answer-a-en-answer_3')), 'Shops set their own hours.');
    await tester.tap(find.byKey(const ValueKey('flash-answer-save')));
    await tester.pumpAndSettle();
    final items = (saved!['items'] as List).cast<Map<String, dynamic>>();
    expect(items.map((i) => i['id']), ['plans', 'login', 'answer_3']);
    expect(items[0]['answer'], {'en': 'New words', 'te': ''});
    expect(items[0]['keywords'], ['plan', 'ప్లాన్', 'plannu']);
    expect(items[1]['active'], isFalse);
    expect(items[2]['chats'], ['user']);
    expect(find.byKey(const ValueKey('flash-answer-note')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('flash-answer-remove-answer_3')));
    await tester.tap(find.byKey(const ValueKey('flash-answer-save')));
    await tester.pumpAndSettle();
    expect((saved!['items'] as List).length, 2);
  });

  testWidgets('Health shows how the chats were answered: free, AI, team', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Store();
    await tester.runAsync(store.init);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SupportChatAnswersCard(
          store: store,
          load: () async => ({'ready': 5, 'free': 3, 'ai': 1, 'team': 1}, {'ready': 40, 'free': 30, 'ai': 20, 'team': 10}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Today: 8 free (5 ready buttons, 3 typed) · 1 by AI · 1 to the team (80% free)'), findsOneWidget);
    expect(find.text('This month: 70 free (40 ready buttons, 30 typed) · 20 by AI · 10 to the team (70% free)'), findsOneWidget);
  });
}
