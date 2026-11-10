import 'package:google_sign_in/google_sign_in.dart';

/// "Continue with Google" on a phone (Android / iOS): the Google side, before Firebase. Kept here so the order of the steps can be
/// tested without a phone (test/google_one_tap_test.dart).

/// The Web client ID of the Firebase project's Google sign-in. Android needs it to ask Google for a sign-in token: without it every
/// "Continue with Google" fails with "serverClientId must be provided on Android" (this is what broke Google sign-in in the store
/// builds). Not a secret; a build can override it with --dart-define=GOOGLE_WEB_CLIENT_ID=... .
const googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '462582150390-u7fubjslhk4htiaga65286iedj3j666f.apps.googleusercontent.com',
);

bool _ready = false;

/// Starts Google sign-in once, with the Web client ID.
Future<void> initGoogleSignIn() async {
  if (_ready) return;
  await GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);
  _ready = true;
}

/// One tap: the sheet of the Google accounts already on this phone (someone coming back with the account they used before is signed
/// in without any tap). Only when that sheet cannot be shown (for example no Google account on the phone yet) does Google's full
/// account picker open, which can also add an account. Null when the person closed the sheet without choosing.
Future<GoogleSignInAccount?> pickGoogleAccount() async {
  await initGoogleSignIn();
  try {
    final quick = await GoogleSignIn.instance.attemptLightweightAuthentication(reportAllExceptions: true);
    if (quick != null) return quick;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    // The sheet is not available here: the full picker below.
  }
  try {
    return await GoogleSignIn.instance.authenticate();
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }
}

/// Signs Google out on this phone, so the next "Continue with Google" shows the account list again instead of signing straight back
/// in (after "Log out", or when a sign-in was refused).
Future<void> forgetGoogleAccount() async {
  try {
    await initGoogleSignIn();
    await GoogleSignIn.instance.signOut();
  } catch (_) {
    /* Nothing to forget. */
  }
}
