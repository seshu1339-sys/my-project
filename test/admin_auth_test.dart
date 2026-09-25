import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/services/admin_route.dart';
import 'package:ecommerce_app/ui/admin_auth.dart';

class AdminTestUser implements User {
  @override
  String get email => 'admin@example.com';
  @override
  bool get emailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdminTestStore extends Store {
  AdminTestStore() : super(live: true);
  User? current;
  String? lastAction;
  String? submittedEmail;
  String? lastCallName;
  Map<String, dynamic>? lastCallData;
  bool failLogin = false, failVerify = false, loggedOut = false;
  Map<String, dynamic> requestOtpResult = const {'ok': true, 'cooldownSeconds': 45, 'expiresInSeconds': 300};

  @override
  User? get user => current;

  @override
  Future<void> login(String email, String password) async {
    lastAction = 'login';
    submittedEmail = email;
    if (failLogin) throw StateError('Incorrect email or password.');
    current = AdminTestUser();
    notifyListeners();
  }

  @override
  Future<bool> refreshEmailVerification() async {
    lastAction = 'refresh';
    notifyListeners();
    return true;
  }

  @override
  Future<void> logout() async {
    lastAction = 'logout';
    loggedOut = true;
    current = null;
    admin = false;
    notifyListeners();
  }

  @override
  Future<void> resetPassword(String email) async {
    lastAction = 'reset';
    submittedEmail = email;
  }

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> data) async {
    lastCallName = name;
    lastCallData = data;
    if (name == 'requestAdminOtp') return requestOtpResult;
    if (name == 'verifyAdminOtp') {
      if (failVerify) throw Exception('Incorrect code. 4 attempt(s) left.');
      return {'ok': true};
    }
    throw StateError('Unexpected call: $name');
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  test('the default admin route is not a guessable path like /admin', () {
    expect(adminRoutePath, isNot('/admin'));
    expect(adminRoutePath, startsWith('/'));
  });

  testWidgets('wrong password shows an error and never reaches the OTP step', (tester) async {
    final store = AdminTestStore()..failLogin = true;
    await tester.pumpWidget(MaterialApp(home: AdminGate(store: store)));
    await tester.enterText(field('Email address'), 'admin@example.com');
    await tester.enterText(field('Password'), 'wrong-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(store.lastAction, 'login');
    expect(field('Verification code'), findsNothing);
    expect(find.textContaining('Incorrect email or password'), findsOneWidget);
  });

  testWidgets('correct password but no admin claim is rejected and signs the account back out', (tester) async {
    final store = AdminTestStore(); // admin stays false (the default)
    await tester.pumpWidget(MaterialApp(home: AdminGate(store: store)));
    await tester.enterText(field('Email address'), 'admin@example.com');
    await tester.enterText(field('Password'), 'correct-but-not-admin');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(store.lastAction, 'logout');
    expect(store.loggedOut, true);
    expect(find.textContaining('Invalid administrator credentials'), findsOneWidget);
    expect(field('Verification code'), findsNothing);
  });

  testWidgets('correct password and admin claim moves to the OTP step and auto-requests a code', (tester) async {
    final store = AdminTestStore()..admin = true;
    await tester.pumpWidget(AdminEntryApp(store: store));
    await tester.enterText(field('Email address'), 'admin@example.com');
    await tester.enterText(field('Password'), 'correct-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(field('Verification code'), findsOneWidget);
    expect(store.lastCallName, 'requestAdminOtp');
    expect(find.textContaining('has been emailed'), findsOneWidget);
  });

  testWidgets('the correct OTP unlocks the dashboard; a wrong one does not', (tester) async {
    var verified = false;
    final store = AdminTestStore()..admin = true;
    await tester.pumpWidget(
      MaterialApp(home: AdminOtpPage(store: store, onVerified: () => verified = true)),
    );
    await tester.pumpAndSettle();
    expect(store.lastCallName, 'requestAdminOtp');

    store.failVerify = true;
    await tester.enterText(field('Verification code'), '000000');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(verified, false);
    expect(find.textContaining('Incorrect code'), findsOneWidget);

    store.failVerify = false;
    await tester.enterText(field('Verification code'), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(verified, true);
    expect(store.lastCallData, {'code': '123456'});
  });

  testWidgets('resend is disabled during the cooldown and re-enables once it elapses', (tester) async {
    final store = AdminTestStore()
      ..admin = true
      ..requestOtpResult = const {'ok': true, 'cooldownSeconds': 3};
    await tester.pumpWidget(
      MaterialApp(home: AdminOtpPage(store: store, onVerified: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resend code (3s)'), findsOneWidget);
    final resendDuringCooldown = tester.widget<TextButton>(find.ancestor(
      of: find.textContaining('Resend code ('),
      matching: find.byType(TextButton),
    ));
    expect(resendDuringCooldown.onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Resend code'), findsOneWidget);
    final resendAfterCooldown = tester.widget<TextButton>(find.ancestor(
      of: find.text('Resend code'),
      matching: find.byType(TextButton),
    ));
    expect(resendAfterCooldown.onPressed, isNotNull);
  });

  testWidgets('forgot password sends a reset email without bypassing the OTP step', (tester) async {
    final store = AdminTestStore();
    await tester.pumpWidget(MaterialApp(home: AdminPasswordPage(store: store)));
    await tester.enterText(field('Email address'), 'admin@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(store.lastAction, 'reset');
    expect(store.submittedEmail, 'admin@example.com');
    expect(find.textContaining('a password reset email has been sent'), findsOneWidget);
    // Resetting the password never itself grants access: no OTP call was made,
    // and this page never shows the dashboard on its own.
    expect(store.lastCallName, isNull);
  });

  testWidgets('signing out from the OTP step returns to the password step, not the dashboard', (tester) async {
    final store = AdminTestStore()..admin = true;
    await tester.pumpWidget(AdminEntryApp(store: store));
    await tester.enterText(field('Email address'), 'admin@example.com');
    await tester.enterText(field('Password'), 'correct-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(field('Verification code'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(store.loggedOut, true);
    expect(field('Password'), findsOneWidget);
    expect(field('Verification code'), findsNothing);
  });
}
