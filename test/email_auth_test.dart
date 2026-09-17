import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/account.dart';
import 'package:ecommerce_app/ui/email_link.dart';

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

  @override
  Future<void> sendSignInLink(String email) async {
    action = 'send-link';
    submittedEmail = email;
  }

  @override
  Future<void> completeSignInLink(String email, String link) async {
    action = 'complete-link';
    submittedEmail = email;
    throw FirebaseAuthException(code: 'expired-action-code');
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
void main() {
  testWidgets(
    'passwordless links send without a password and handle expired links',
    (tester) async {
      final store = EmailTestStore();
      await tester.pumpWidget(MaterialApp(home: EmailLinkPage(store: store)));
      expect(field('Password'), findsNothing);
      await tester.enterText(field('Email address'), 'customer@example.com');
      await tester.tap(find.text('Send sign-in link'));
      await tester.pumpAndSettle();
      expect(store.action, 'send-link');
      expect(find.textContaining('Sign-in link sent'), findsOneWidget);
      await tester.tap(find.text('I already have a sign-in link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        field('Sign-in link'),
        'https://example.test/?mode=signIn&oobCode=expired',
      );
      await tester.tap(find.text('Complete sign-in'));
      await tester.pumpAndSettle();
      expect(store.action, 'complete-link');
      expect(find.textContaining('expired, or already used'), findsOneWidget);
      expect(store.submittedEmail, 'customer@example.com');
    },
  );
  testWidgets('incoming link asks for email on a different device', (
    tester,
  ) async {
    final store = EmailTestStore()
      ..pendingEmailLink = 'https://example.test/?mode=signIn&oobCode=code';
    await tester.pumpWidget(MaterialApp(home: EmailLinkPage(store: store)));
    expect(find.text('Confirm your email to sign in'), findsOneWidget);
    await tester.tap(find.text('Complete sign-in'));
    await tester.pumpAndSettle();
    expect(store.action, isNull);
    expect(find.textContaining('Enter the email address'), findsOneWidget);
  });
  testWidgets('email login and reset use entered address without SMS fields', (
    tester,
  ) async {
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
}
