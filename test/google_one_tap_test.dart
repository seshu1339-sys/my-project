import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:ecommerce_app/services/google_account.dart';

/// Google's account sheet on the phone, faked: what it would do, and what the app asked of it.
class FakeGoogle extends GoogleSignInPlatform {
  final steps = <String>[];
  InitParameters? initParams;
  AuthenticationResults? sheetAnswer;
  GoogleSignInException? sheetError;
  AuthenticationResults? pickerAnswer;
  GoogleSignInException? pickerError;

  static AuthenticationResults account(String email) => AuthenticationResults(
    user: GoogleSignInUserData(email: email, id: 'id-$email'),
    authenticationTokens: AuthenticationTokenData(idToken: 'token-$email'),
  );

  @override
  Future<void> init(InitParameters params) async {
    steps.add('init');
    initParams = params;
  }

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) async {
    steps.add('sheet');
    if (sheetError != null) throw sheetError!;
    return sheetAnswer;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    steps.add('picker');
    if (pickerError != null) throw pickerError!;
    return pickerAnswer!;
  }

  @override
  bool authorizationRequiresUserInteraction() => false;
  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(ClientAuthorizationTokensForScopesParameters params) async => null;
  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(ServerAuthorizationTokensForScopesParameters params) async => null;
  @override
  Future<void> signOut(SignOutParams params) async => steps.add('signOut');
  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

void main() {
  late FakeGoogle google;
  setUp(() {
    google = FakeGoogle();
    GoogleSignInPlatform.instance = google;
  });

  test('Google is started with the Web client ID (without it Android refuses every sign-in)', () async {
    google.sheetAnswer = FakeGoogle.account('a@example.com');
    await pickGoogleAccount();
    expect(google.steps.first, 'init');
    expect(google.initParams?.serverClientId, '462582150390-u7fubjslhk4htiaga65286iedj3j666f.apps.googleusercontent.com');
    expect(googleWebClientId, endsWith('.apps.googleusercontent.com'));
  });

  test('one tap: an account from the sheet of accounts on the phone signs in, with no picker and no typing', () async {
    google.sheetAnswer = FakeGoogle.account('seller@example.com');
    final account = await pickGoogleAccount();
    expect(account?.email, 'seller@example.com');
    expect(account?.authentication.idToken, 'token-seller@example.com');
    expect(google.steps.where((s) => s != 'init'), ['sheet']);
  });

  test('closing the sheet signs nobody in and opens nothing else', () async {
    google.sheetError = const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
    expect(await pickGoogleAccount(), isNull);
    expect(google.steps.where((s) => s != 'init'), ['sheet']);
  });

  test('no account to show in the sheet: Google\'s full account picker opens instead', () async {
    google.pickerAnswer = FakeGoogle.account('new@example.com');
    final account = await pickGoogleAccount();
    expect(account?.email, 'new@example.com');
    expect(google.steps.where((s) => s != 'init'), ['sheet', 'picker']);
  });

  test('the sheet is not available here: the full picker opens; closing it signs nobody in', () async {
    google.sheetError = const GoogleSignInException(code: GoogleSignInExceptionCode.uiUnavailable);
    google.pickerError = const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
    expect(await pickGoogleAccount(), isNull);
    expect(google.steps.where((s) => s != 'init'), ['sheet', 'picker']);
  });

  test('a set-up problem is reported (shown with its code), not silently swallowed', () async {
    google.pickerError = const GoogleSignInException(code: GoogleSignInExceptionCode.clientConfigurationError, description: 'serverClientId must be provided on Android');
    await expectLater(pickGoogleAccount(), throwsA(isA<GoogleSignInException>().having((e) => e.code, 'code', GoogleSignInExceptionCode.clientConfigurationError)));
  });

  test('forgetting the account signs Google out, so the next sign-in shows the accounts again', () async {
    await forgetGoogleAccount();
    expect(google.steps.last, 'signOut');
  });
}
