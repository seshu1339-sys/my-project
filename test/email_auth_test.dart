import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/account.dart';
import 'package:ecommerce_app/ui/sign_in_panel.dart';

class EmailTestUser implements User {
  @override
  String get email => 'owner@example.com';
  @override
  bool get emailVerified => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EmailTestStore extends Store {
  EmailTestStore() : super(live: true);
  User? current;
  String? action;
  String? submittedEmail;
  @override
  User? get user => current;
  @override
  Future<void> login(String email, String password) async {
    action = 'login';
    submittedEmail = email;
  }

  @override
  Future<void> registerEmail(String email, String password) async {
    action = 'register';
    submittedEmail = email;
    current = EmailTestUser();
    notifyListeners();
  }

  void signOutForTest() {
    current = null;
    notifyListeners();
  }

  /// What Log out leaves behind for the sign-in screen (Store.logout itself needs Firebase).
  void loggedOutForTest() => googleOpenedByItself();

  @override
  Future<void> resetPassword(String email) async {
    action = 'reset';
    submittedEmail = email;
  }

  @override
  Future<void> sendVerificationEmail() async {
    action = 'resend';
  }

  @override
  Future<bool> refreshEmailVerification() async {
    action = 'refresh';
    return false;
  }

  bool? googleResult = true;
  Object? googleError;
  /// Each Google sign-in asked for: true when it was the sheet opening by itself.
  final googleCalls = <bool>[];
  String? codeSentTo, codeTyped;
  @override
  Future<bool?> signInWithGoogle({bool automatic = false}) async {
    action = 'google';
    googleCalls.add(automatic);
    if (googleError != null) throw googleError!;
    return googleResult;
  }

  @override
  Future<void> requestEmailCode(String email) async {
    action = 'send-code';
    codeSentTo = email;
  }

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    action = 'verify-code';
    codeTyped = code;
    submittedEmail = email;
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
/// The sign-in form is now taller (Google button on top), so these tests use a tall screen.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _panel(WidgetTester tester, EmailTestStore store) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SignInPanel(store: store)))));
  await tester.pumpAndSettle();
}

/// The email code once Google was closed: the link, then the code form.
Future<void> _openEmailCode(WidgetTester tester, EmailTestStore store) async {
  store.googleResult = false;
  await _panel(tester, store);
  await tester.tap(find.byKey(const ValueKey('email-code-toggle')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first open: the Google sheet opens by itself, and while Google works there is no email code', (tester) async {
    final store = EmailTestStore();
    await _panel(tester, store);
    expect(store.googleCalls, [true], reason: "the sheet with the phone's account opened by itself: one tap to sign in");
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const ValueKey('email-code-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('code-email')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('google-sign-in')));
    await tester.pumpAndSettle();
    expect(store.googleCalls, [true, false], reason: "the button asks again, with Google's full picker when needed");
    expect(find.byKey(const ValueKey('email-code-toggle')), findsNothing);
  });
  testWidgets('the sheet opens by itself once per run of the app, and not right after Log out', (tester) async {
    final store = EmailTestStore();
    await _panel(tester, store);
    await tester.pumpWidget(const SizedBox());
    await _panel(tester, store);
    expect(store.googleCalls, [true], reason: 'a second sign-in screen in the same run does not pop Google up again');
    final fresh = EmailTestStore()..loggedOutForTest();
    await _panel(tester, fresh);
    expect(fresh.googleCalls, isEmpty, reason: 'after Log out the person taps Google themselves');
  });
  testWidgets('closing the Google sheet offers the email code', (tester) async {
    final store = EmailTestStore()..googleResult = false;
    await _panel(tester, store);
    expect(store.emailCodeOffered, isTrue);
    expect(find.byKey(const ValueKey('email-code-toggle')), findsOneWidget);
  });
  testWidgets('Google not working offers the email code, with the reason', (tester) async {
    final store = EmailTestStore()..googleError = StateError('Google did not send a sign-in token. Please try again, or use an email code.');
    await _panel(tester, store);
    expect(find.byKey(const ValueKey('sign-in-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('email-code-toggle')), findsOneWidget);
  });
  testWidgets("the website's One Tap prompt waiting for a click offers nothing else yet", (tester) async {
    final store = EmailTestStore()..googleResult = null;
    await _panel(tester, store);
    expect(store.googleCalls, [true]);
    expect(find.byKey(const ValueKey('email-code-toggle')), findsNothing);
  });
  testWidgets('the email code backup sends a code, then signs in with the 6 digits', (tester) async {
    final store = EmailTestStore();
    await _openEmailCode(tester, store);
    await tester.enterText(find.byKey(const ValueKey('code-email')), 'not an email');
    await tester.tap(find.byKey(const ValueKey('send-code')));
    await tester.pumpAndSettle();
    expect(store.action, isNot('send-code'));
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('code-email')), 'customer@example.com');
    await tester.tap(find.byKey(const ValueKey('send-code')));
    await tester.pumpAndSettle();
    expect(store.codeSentTo, 'customer@example.com');
    await tester.enterText(find.byKey(const ValueKey('code-field')), '12');
    await tester.tap(find.byKey(const ValueKey('verify-code')));
    await tester.pumpAndSettle();
    expect(store.action, 'send-code', reason: 'a short code is not submitted');
    await tester.enterText(find.byKey(const ValueKey('code-field')), '123456');
    await tester.tap(find.byKey(const ValueKey('verify-code')));
    await tester.pumpAndSettle();
    expect(store.action, 'verify-code');
    expect(store.codeTyped, '123456');
    expect(store.submittedEmail, 'customer@example.com');
  });
  testWidgets("a blocked role is told so on the sign-in screen (the same email's other roles are not affected)", (tester) async {
    final store = EmailTestStore()..roleBlock = 'Your staff account is blocked. Contact LOCAMARKET support.';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SignInPanel(store: store, opensGoogle: false))));
    expect(find.byKey(const ValueKey('sign-in-error')), findsOneWidget);
    expect(find.textContaining('staff account is blocked'), findsOneWidget);
    expect(find.textContaining('another role'), findsNothing);
  });
  testWidgets('the email code starts with the last email used on this phone', (tester) async {
    final store = EmailTestStore()..lastSignInEmail = 'same.person@example.com';
    await _openEmailCode(tester, store);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('code-email'))).controller!.text, 'same.person@example.com');
    await tester.tap(find.byKey(const ValueKey('send-code')));
    await tester.pumpAndSettle();
    expect(store.codeSentTo, 'same.person@example.com', reason: 'no typing needed');
  });
  testWidgets('the customer Account page: Google sign-in only, no password form, no registration, no reset email', (tester) async {
    tallScreen(tester);
    final store = EmailTestStore();
    await tester.pumpWidget(MaterialApp(home: AccountPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(field('Password'), findsNothing);
    expect(field('Email address'), findsNothing, reason: 'the email-code field only appears once Google did not work');
    expect(find.text('Create an account'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
    expect(find.text('Send SMS code'), findsNothing);
    expect(store.googleCalls, isEmpty, reason: 'Account does not pop Google up by itself; only the first open does');
  });
}
