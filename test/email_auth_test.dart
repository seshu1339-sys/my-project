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

  bool googleResult = true;
  String? codeSentTo, codeTyped;
  @override
  Future<bool> signInWithGoogle() async {
    action = 'google';
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

void main() {
  testWidgets('Google is the main sign-in; the email code is only a backup', (tester) async {
    final store = EmailTestStore();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SignInPanel(store: store))));
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const ValueKey('code-email')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('google-sign-in')));
    await tester.pumpAndSettle();
    expect(store.action, 'google');
  });
  testWidgets('the email code backup sends a code, then signs in with the 6 digits', (tester) async {
    final store = EmailTestStore();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SignInPanel(store: store)))));
    await tester.tap(find.byKey(const ValueKey('email-code-toggle')));
    await tester.pumpAndSettle();
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
  testWidgets('an email refused for holding another role is told so', (tester) async {
    final store = EmailTestStore()..roleBlock = 'This email is already registered in another role. Please use a different email.';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SignInPanel(store: store))));
    expect(find.byKey(const ValueKey('sign-in-error')), findsOneWidget);
    expect(find.textContaining('already registered in another role'), findsOneWidget);
  });
  testWidgets('email login and reset use entered address without SMS fields', (
    tester,
  ) async {
    tallScreen(tester);
    final store = EmailTestStore();
    await tester.pumpWidget(MaterialApp(home: AccountPage(store: store)));
    expect(find.text('Send SMS code'), findsNothing);
    await tester.enterText(field('Email address'), 'customer@example.com');
    await tester.enterText(field('Password'), 'example-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(store.action, 'login');
    expect(store.submittedEmail, 'customer@example.com');
      await tester.ensureVisible(find.text('Forgot password?'));
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(store.action, 'reset');
  });
  testWidgets(
    'registration validates confirmation and shows verification gate',
    (tester) async {
    tallScreen(tester);
      final store = EmailTestStore();
      await tester.pumpWidget(MaterialApp(home: AccountPage(store: store)));
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email address'), 'owner@example.com');
      await tester.enterText(field('Password'), 'example-password');
      await tester.enterText(field('Confirm password'), 'different');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(store.action, isNull);
      expect(find.textContaining('Passwords do not match'), findsOneWidget);
      await tester.enterText(field('Confirm password'), 'example-password');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(store.action, 'register');
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('Your orders'), findsNothing);
      await tester.tap(find.text('Resend verification email'));
      await tester.pumpAndSettle();
      expect(store.action, 'resend');
      await tester.tap(find.text('I have verified my email'));
      await tester.pumpAndSettle();
      expect(store.action, 'refresh');
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('Your orders'), findsNothing);
    },
  );
  testWidgets('after registering and signing out, the sign-in form is shown, not registration', (
    tester,
  ) async {
    tallScreen(tester);
    final store = EmailTestStore();
    await tester.pumpWidget(MaterialApp(home: AccountPage(store: store)));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Email address'), 'owner@example.com');
    await tester.enterText(field('Password'), 'example-password');
    await tester.enterText(field('Confirm password'), 'example-password');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(store.action, 'register');
    store.signOutForTest();
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsNothing);
    expect(find.text('Welcome to your neighbourhood'), findsOneWidget);
    expect(field('Confirm password'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
