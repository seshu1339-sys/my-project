// The customer app and the website, first open after install: a sign-in sheet with Google's one-tap sheet, shown once on the phone,
// closing by itself once signed in; never for someone already signed in, and never again after the first time.
import 'package:ecommerce_app/data/store.dart';
import 'package:ecommerce_app/ui/first_open_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedInUser implements User {
  @override
  String get uid => 'customer-1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FirstOpenStore extends Store {
  _FirstOpenStore() : super(live: true);
  User? current;
  final googleCalls = <bool>[];
  @override
  User? get user => current;
  @override
  Future<bool?> signInWithGoogle({bool automatic = false}) async {
    googleCalls.add(automatic);
    // The person tapped the account in Google's sheet.
    current = _SignedInUser();
    notifyListeners();
    return true;
  }
}

Future<void> _open(WidgetTester tester, Store store) async {
  await tester.pumpWidget(MaterialApp(home: FirstOpenSignIn(store: store, child: const Scaffold(body: Text('the shop')))));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first open: the sign-in sheet opens with Google by itself, one tap signs in, and the sheet closes', (tester) async {
    final store = _FirstOpenStore();
    await _open(tester, store);
    expect(store.googleCalls, [true], reason: "Google's sheet with the phone's email opened by itself");
    expect(find.byKey(const ValueKey('first-open-sign-in')), findsNothing, reason: 'signed in, so the sheet closed by itself');
    expect(find.text('the shop'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('firstOpenSignInShown'), isTrue);
  });

  testWidgets('"Not now" lets the person shop; the sheet never opens by itself again', (tester) async {
    final fresh = _NoGoogleStore();
    await _open(tester, fresh);
    expect(find.byKey(const ValueKey('first-open-sign-in')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('first-open-not-now')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('first-open-sign-in')), findsNothing);
    expect(find.text('the shop'), findsOneWidget);
    expect(fresh.offersSignInOnFirstOpen, isFalse, reason: 'remembered on this phone');
  });

  testWidgets('a later open (the sheet was shown before on this phone) goes straight to the shop', (tester) async {
    SharedPreferences.setMockInitialValues({'firstOpenSignInShown': true});
    final store = _NoGoogleStore();
    await store.loadFirstOpenForTest();
    await _open(tester, store);
    expect(find.byKey(const ValueKey('first-open-sign-in')), findsNothing);
    expect(store.googleCalls, isEmpty);
  });

  testWidgets('someone already signed in is never asked', (tester) async {
    final store = _FirstOpenStore()..current = _SignedInUser();
    await _open(tester, store);
    expect(find.byKey(const ValueKey('first-open-sign-in')), findsNothing);
    expect(store.googleCalls, isEmpty);
  });

  test('only the customer app (and website) opens it; the vendor and staff apps go to their sign-in screen', () {
    expect((_FirstOpenStore()..appRole = 'vendor').offersSignInOnFirstOpen, isFalse);
    expect((_FirstOpenStore()..appRole = 'staff').offersSignInOnFirstOpen, isFalse);
    expect(_FirstOpenStore().offersSignInOnFirstOpen, isTrue);
  });
}

/// Google closed without choosing: the person stays on the welcome sheet.
class _NoGoogleStore extends _FirstOpenStore {
  @override
  Future<bool?> signInWithGoogle({bool automatic = false}) async {
    googleCalls.add(automatic);
    return false;
  }

  /// What Store.init reads from the phone (Store.init itself needs Firebase).
  Future<void> loadFirstOpenForTest() async {
    if ((await SharedPreferences.getInstance()).getBool('firstOpenSignInShown') ?? false) await firstOpenSignInShown();
  }
}
