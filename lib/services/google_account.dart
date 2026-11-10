import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:google_sign_in/google_sign_in.dart';

/// "Continue with Google": the Google side, before Firebase. Kept here so the order of the steps can be tested without a phone
/// (test/google_one_tap_test.dart).

/// The Web client ID of the Firebase project's Google sign-in. Android needs it to ask Google for a sign-in token: without it every
/// "Continue with Google" fails with "serverClientId must be provided on Android" (this is what broke Google sign-in in the store
/// builds). The website's One Tap prompt uses the same ID. Not a secret; a build can override it with --dart-define=GOOGLE_WEB_CLIENT_ID=... .
const googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '462582150390-u7fubjslhk4htiaga65286iedj3j666f.apps.googleusercontent.com',
);

bool _ready = false;

/// Tests only: lets [initGoogleSignIn] run again (with a new fake Google).
@visibleForTesting
void resetGoogleSignInForTest() => _ready = false;

/// Starts Google sign-in once, with the Web client ID: as the server client on a phone, as the page's own client on the website
/// (Google refuses a server client ID there).
Future<void> initGoogleSignIn({bool web = kIsWeb}) async {
  if (_ready) return;
  await (web
      ? GoogleSignIn.instance.initialize(clientId: googleWebClientId)
      : GoogleSignIn.instance.initialize(serverClientId: googleWebClientId));
  _ready = true;
}

/// One tap: the sheet of the Google accounts already on this phone, with the email shown (someone coming back with the account they
/// used before is signed in without any tap). Unless [sheetOnly] (the sheet that opens by itself), Google's full account picker opens
/// when that sheet cannot be shown, for example with no Google account on the phone yet; it can also add one.
/// Null when the person closed the sheet without choosing, or (with [sheetOnly]) when there is no sheet to show.
Future<GoogleSignInAccount?> pickGoogleAccount({bool sheetOnly = false}) async {
  await initGoogleSignIn();
  try {
    final quick = await GoogleSignIn.instance.attemptLightweightAuthentication(reportAllExceptions: true);
    if (quick != null || sheetOnly) return quick;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled || sheetOnly) return null;
    // The sheet is not available here: the full picker below.
  }
  try {
    return await GoogleSignIn.instance.authenticate();
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }
}

/// The website: Google's One Tap prompt (the browser's signed-in Google account, with its email shown, one click). Its answer does not
/// come back here but on [googleIdTokens], whenever the person clicks; it may never come.
Future<void> showWebOneTap() async {
  await initGoogleSignIn();
  await GoogleSignIn.instance.attemptLightweightAuthentication();
}

/// The Google sign-in tokens of the accounts people choose in the website's One Tap prompt.
Stream<String> googleIdTokens() => GoogleSignIn.instance.authenticationEvents
    .where((event) => event is GoogleSignInAuthenticationEventSignIn)
    .map((event) => (event as GoogleSignInAuthenticationEventSignIn).user.authentication.idToken ?? '')
    .where((token) => token.isNotEmpty);

/// Signs Google out on this phone or in this browser, so the next "Continue with Google" shows the account list again instead of
/// signing straight back in (after "Log out", or when a sign-in was refused).
Future<void> forgetGoogleAccount() async {
  try {
    await initGoogleSignIn();
    await GoogleSignIn.instance.signOut();
  } catch (_) {
    /* Nothing to forget. */
  }
}
