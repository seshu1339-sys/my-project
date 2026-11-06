import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/modules/flash/admin_flash_chat.dart';
import 'package:ecommerce_app/modules/flash/admin_flash_settings.dart';
import 'package:ecommerce_app/modules/flash/flash_chat_page.dart';
import 'package:ecommerce_app/modules/flash/flash_conversation.dart';
import 'package:ecommerce_app/modules/flash/flash_data.dart';
import 'package:ecommerce_app/modules/flash/flash_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget page(Widget child) => MaterialApp(home: Scaffold(body: child));

void sized(WidgetTester tester, [Size size = const Size(1000, 1800)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const talk = [FlashMessage(role: 'user', text: 'Where is my order?'), FlashMessage(role: 'flash', text: 'It is confirmed by the shop.')];

FlashConversationView conversation({List<FlashMessage> messages = talk, String status = 'open', Future<void> Function(String)? onSend, Future<void> Function()? onSolved, Future<void> Function()? onUnsolved}) => FlashConversationView(
  messages: messages,
  status: status,
  onSend: onSend ?? (_) async {},
  onSolved: onSolved ?? () async {},
  onUnsolved: onUnsolved ?? () async {},
);

const ticket = FlashTicket(id: 'user_c1', chatId: 'c1', category: 'Orders', text: 'I want a refund', who: 'Ravi', email: 'r@example.com', summary: 'Wants a refund', reason: 'person');

AdminFlashChatView admin({FlashCounts counts = const FlashCounts(), List<FlashTicket> tickets = const [], List<FlashChat> solved = const [], Stream<FlashTriage?> Function(String)? triageOf, Future<void> Function(String, String)? onClose, Future<void> Function(String)? onVerify}) => AdminFlashChatView(
  counts: counts,
  tickets: tickets,
  solved: solved,
  triageOf: triageOf ?? (_) => Stream.value(null),
  messagesOf: (_) async => talk,
  onClose: onClose ?? (_, _) async {},
  onVerify: onVerify ?? (_) async {},
);

void main() {
  test('the five chats are separate, with the same categories as the server', () {
    expect(flashRoute, '/flash');
    expect([for (final chat in flashChats) chat.kind], ['user', 'vendor', 'premium', 'provider', 'staff']);
    expect([for (final chat in flashChats) chat.categories], [
      ['Search & shops', 'Offers', 'Services', 'App', 'Orders', 'Other'],
      ['Login', 'Plans & prices', 'Items & photos', 'Offers', 'Payment', 'Shop', 'Other'],
      ['My plan', 'My stats', 'Ads & offers', 'Wholesale', 'Items & prices', 'Payment', 'Other'],
      ['Login', 'My listing', 'Charge per hour', 'App', 'Other'],
      ['My area', 'Targets', 'Missed days', 'Adding offers', 'Terms', 'Account', 'App', 'Other'],
    ]);
    expect({for (final chat in flashChats) chat.collection}, {'flashUserChats', 'flashVendorChats', 'flashPremiumChats', 'flashProviderChats', 'flashStaffChats'});
    expect({for (final chat in flashChats) chat.callable}, {'flashUserChat', 'flashVendorChat', 'flashPremiumChat', 'flashProviderChat', 'flashStaffChat'});
    expect({for (final chat in flashChats) chat.route}.length, 5);
    expect([for (final chat in flashChats) if (chat.officeContact) chat.kind], ['premium']);
  });

  test('every app opens its chat from the floating Help button on its main screen (owner decision, 6 Nov 2026)', () {
    final uses = {
      'lib/ui/storefront.dart': 'customerFlashButton',
      'lib/ui/vendor_home.dart': 'vendorAppFlashButton',
      'lib/ui/vendor_page.dart': 'vendorAppFlashButton',
      'lib/ui/provider_page.dart': 'vendorAppFlashButton',
      'lib/ui/field_home_page.dart': 'staffAppFlashButton',
    };
    for (final e in uses.entries) {
      expect(File(e.key).readAsStringSync().contains(e.value), isTrue, reason: e.key);
    }
  });

  testWidgets('the Help button: signed out it asks to sign in, never opening a chat', (tester) async {
    var signIn = 0, opened = 0;
    final store = Store();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        floatingActionButton: FlashChatButton(store: store, chooseSetup: () async => flashChats.first, open: (_, _) async => opened++, onSignIn: (_) async => signIn++),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('flash-chat-button')));
    await tester.pump();
    expect(signIn, 1);
    expect(opened, 0);
    store.dispose();
  });

  test('the Support Inbox: Premium vendors first, then the oldest', () {
    final old = FlashTicket(id: 'user_a', chatId: 'a', category: 'App', text: 'x', kind: 'user', at: DateTime(2026, 11, 1));
    final newer = FlashTicket(id: 'staff_b', chatId: 'b', category: 'App', text: 'x', kind: 'staff', at: DateTime(2026, 11, 3));
    final premiumNew = FlashTicket(id: 'premium_c', chatId: 'c', category: 'Payment', text: 'x', kind: 'premium', priority: true, at: DateTime(2026, 11, 5));
    expect([for (final t in inboxOrder([newer, old, premiumNew])) t.id], ['premium_c', 'user_a', 'staff_b']);
  });

  testWidgets('the Support Inbox filters by role and answers from one place', (tester) async {
    sized(tester);
    final closed = <String>[];
    final tickets = [
      FlashTicket(id: 'user_a', chatId: 'a', category: 'App', text: 'how to search', kind: 'user', at: DateTime(2026, 11, 1)),
      FlashTicket(id: 'premium_c', chatId: 'c', category: 'Payment', text: 'money', kind: 'premium', priority: true, at: DateTime(2026, 11, 5)),
      FlashTicket(id: 'provider_d', chatId: 'd', category: 'Login', text: 'login', kind: 'provider', at: DateTime(2026, 11, 2)),
    ];
    await tester.pumpWidget(page(FlashSupportInboxView(
      tickets: tickets,
      roles: {for (final chat in flashChats) chat.kind: chat.adminTitle},
      triageOf: (_) => Stream.value(null),
      messagesOf: (_) async => talk,
      onClose: (id, reply) async => closed.add(id),
    )));
    expect(find.text('3 unanswered. Premium vendors first, then the oldest.'), findsOneWidget);
    expect(find.text('Premium vendors • PRIORITY'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('flash-ticket-premium_c'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('flash-ticket-user_a'))).dy));
    await tester.tap(find.byKey(const ValueKey('flash-inbox-provider')));
    await tester.pump();
    expect(find.byKey(const ValueKey('flash-ticket-provider_d')), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-ticket-user_a')), findsNothing);
    expect(find.text('Services (1)'), findsOneWidget);
  });

  testWidgets("the Premium chat shows the office's Call and WhatsApp", (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(page(FlashOfficeContactView(phone: '98765 43210', whatsapp: '', launch: (uri) async => opened.add(uri))));
    await tester.tap(find.byKey(const ValueKey('flash-office-call')));
    await tester.tap(find.byKey(const ValueKey('flash-office-whatsapp')));
    expect(opened.map((u) => u.toString()), ['tel:9876543210', 'https://wa.me/919876543210']);
    await tester.pumpWidget(page(const FlashOfficeContactView(phone: '', whatsapp: '')));
    expect(find.byKey(const ValueKey('flash-office')), findsNothing);
  });

  test('pending is what came in and is not solved', () {
    final counts = FlashCounts.fromData({'cameIn': 10, 'solved': 7, 'verified': 2});
    expect(counts.pending, 3);
    expect(FlashCounts.fromData(null).pending, 0);
  });

  testWidgets('the list starts a chat by category and opens an earlier one', (tester) async {
    sized(tester, const Size(320, 700));
    final started = <String>[];
    final opened = <String>[];
    await tester.pumpWidget(page(FlashChatListView(
      categories: const ['Payment', 'Plan', 'Offers', 'Shop', 'Other'],
      chats: const [FlashChat(id: 'c1', category: 'Plan', status: 'ticket')],
      onNew: started.add,
      onOpen: (chat) => opened.add(chat.id),
    )));
    await tester.tap(find.byKey(const ValueKey('flash-new-Payment')));
    await tester.tap(find.byKey(const ValueKey('flash-chat-c1')));
    expect(started, ['Payment']);
    expect(opened, ['c1']);
    expect(find.textContaining('With our team'), findsOneWidget);
  });

  testWidgets('a person sends a message and can say whether it was solved', (tester) async {
    sized(tester, const Size(320, 700));
    final sent = <String>[];
    var solved = 0, unsolved = 0;
    await tester.pumpWidget(page(conversation(onSend: (text) async => sent.add(text), onSolved: () async => solved++, onUnsolved: () async => unsolved++)));
    expect(find.text('Flash'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('flash-text')), '  Thank you  ');
    await tester.tap(find.byKey(const ValueKey('flash-send')));
    await tester.pumpAndSettle();
    expect(sent, ['Thank you']);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('flash-text'))).controller!.text, '');
    await tester.tap(find.byKey(const ValueKey('flash-solved')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('flash-unsolved')));
    await tester.pumpAndSettle();
    expect([solved, unsolved], [1, 1]);
  });

  testWidgets('while Flash replies the message shows and nothing can be sent twice', (tester) async {
    sized(tester);
    final reply = Completer<void>();
    final sent = <String>[];
    await tester.pumpWidget(page(conversation(messages: const [], onSend: (text) {
      sent.add(text);
      return reply.future;
    })));
    await tester.enterText(find.byKey(const ValueKey('flash-text')), 'hello');
    await tester.tap(find.byKey(const ValueKey('flash-send')));
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-busy')), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('flash-send'))).onPressed, isNull);
    reply.complete();
    await tester.pumpAndSettle();
    expect(sent, ['hello']);
  });

  testWidgets('a refused message stays in the box and the server\'s reason shows', (tester) async {
    sized(tester);
    await tester.pumpWidget(page(conversation(onSend: (_) async => throw FirebaseFunctionsException(code: 'failed-precondition', message: 'used today\'s messages'))));
    await tester.enterText(find.byKey(const ValueKey('flash-text')), 'my words');
    await tester.tap(find.byKey(const ValueKey('flash-send')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('flash-text'))).controller!.text, 'my words');
    expect(find.textContaining('used today'), findsOneWidget);
    expect(find.textContaining('firebase_functions'), findsNothing);
  });

  testWidgets('with the team or finished, the box closes', (tester) async {
    sized(tester);
    await tester.pumpWidget(page(conversation(status: 'ticket')));
    expect(find.byKey(const ValueKey('flash-with-team')), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-text')), findsNothing);
    expect(find.byKey(const ValueKey('flash-solved')), findsNothing);
    await tester.pumpWidget(page(conversation(status: 'closed', messages: const [...talk, FlashMessage(role: 'admin', text: 'We fixed it.')])));
    expect(find.text('LOCAMARKET team'), findsOneWidget);
    expect(find.text('We fixed it.'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-finished')), findsOneWidget);
  });

  testWidgets('the admin sees the counts of this chat type', (tester) async {
    sized(tester, const Size(320, 900));
    await tester.pumpWidget(page(admin(counts: const FlashCounts(cameIn: 12, solved: 8, verified: 3))));
    Text value(String id) => tester.widget<Text>(find.byKey(ValueKey(id)));
    expect(value('flash-came-in').data, '12');
    expect(value('flash-solved-count').data, '8');
    expect(value('flash-pending').data, '4');
    expect(value('flash-verified-count').data, '3');
    expect(find.byKey(const ValueKey('flash-no-tickets')), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-none-solved')), findsOneWidget);
  });

  testWidgets('a ticket shows the problem and the AI suggestion, and only the admin\'s answer closes it', (tester) async {
    sized(tester);
    final closed = <List<String>>[];
    await tester.pumpWidget(page(admin(
      tickets: const [ticket],
      triageOf: (_) => Stream.value(const FlashTriage(type: 'order', urgency: 'high', suggestion: 'Ask the shop first.')),
      onClose: (id, reply) async => closed.add([id, reply]),
    )));
    await tester.pump();
    expect(find.text('I want a refund'), findsOneWidget);
    expect(find.textContaining('Ravi · r@example.com'), findsOneWidget);
    expect(find.textContaining('The person said Flash did not solve it'), findsOneWidget);
    expect(find.textContaining('AI suggestion, nothing has been done: order, high urgency. Ask the shop first.'), findsOneWidget);
    expect(closed, isEmpty);

    await tester.tap(find.byKey(const ValueKey('flash-close-user_c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('flash-answer')), ' Refund is on its way. ');
    await tester.tap(find.byKey(const ValueKey('flash-answer-send')));
    await tester.pumpAndSettle();
    expect(closed, [['user_c1', 'Refund is on its way.']]);
  });

  testWidgets('a ticket says when AI has not read it or could not', (tester) async {
    sized(tester);
    await tester.pumpWidget(page(admin(tickets: const [ticket])));
    await tester.pump();
    expect(find.text('AI is reading this ticket...'), findsOneWidget);
    await tester.pumpWidget(page(admin(tickets: const [FlashTicket(id: 'user_c2', chatId: 'c2', category: 'App', text: 'x')], triageOf: (_) => Stream.value(const FlashTriage(failed: true)))));
    await tester.pump();
    expect(find.text('AI could not read this ticket.'), findsOneWidget);
  });

  testWidgets('the admin reads what Flash solved and marks it Verified', (tester) async {
    sized(tester);
    final verified = <String>[];
    await tester.pumpWidget(page(admin(solved: const [FlashChat(id: 'c9', category: 'App', status: 'solved', who: 'Ravi')], onVerify: (id) async => verified.add(id))));
    await tester.tap(find.byKey(const ValueKey('flash-view-c9')));
    await tester.pumpAndSettle();
    expect(find.text('Person: Where is my order?'), findsOneWidget);
    expect(find.text('Flash: It is confirmed by the shop.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('flash-verify-c9')));
    await tester.pumpAndSettle();
    expect(verified, ['c9']);
  });

  testWidgets('the settings show the saved values and save the limit and the help texts', (tester) async {
    sized(tester, const Size(320, 900));
    final saved = <Map<String, dynamic>>[];
    await tester.pumpWidget(page(AdminFlashSettings(config: const FlashConfig(dailyMessages: 30, helpUser: 'saved help'), onSave: (fields) async => saved.add(fields))));
    expect(find.text('saved help'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('flash-limit')), '12');
    await tester.enterText(find.byKey(const ValueKey('flash-help-vendor')), 'vendor help');
    // The longer form scrolls: the Save button is built once it is near.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('flash-save')), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('flash-save')));
    await tester.pumpAndSettle();
    expect(saved.single, {'dailyMessages': 12, 'helpUser': 'saved help', 'helpVendor': 'vendor help', 'helpStaff': '', 'helpPremium': '', 'helpProvider': '', 'supportPhone': '', 'supportWhatsapp': ''});
  });

  testWidgets('a limit that is not a number is not saved', (tester) async {
    sized(tester);
    final saved = <Map<String, dynamic>>[];
    await tester.pumpWidget(page(AdminFlashSettings(config: const FlashConfig(), onSave: (fields) async => saved.add(fields))));
    await tester.enterText(find.byKey(const ValueKey('flash-limit')), 'many');
    await tester.tap(find.byKey(const ValueKey('flash-save')));
    await tester.pump();
    expect(saved, isEmpty);
    expect(find.text('The daily limit must be a number.'), findsOneWidget);
  });
}
