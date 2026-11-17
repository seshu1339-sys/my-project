// The cause of a problem a person meets in an app (AI Agent + Health System part 2, 17 Nov 2026), worked out on the device from what
// it knows (the error code, the internet, location and permissions), and whether the AI Support box should open for it. Pure: no
// Flutter, no Firebase, so every rule is tested on its own.
//
//   USER side    the person can fix it: no internet, slow internet, location off / not allowed, a permission refused, a photo too big,
//                the session ran out, a field missing, a wrong code, too many tries, Google sign-in closed
//   OUR side     ours to fix: the server broke, a code bug, a crash, a hang, a screen stuck loading, a slow save, no answer to a tap
//   DEVICE side  decided on the server, when the people it happens to are almost all on one phone model or Android version
//                (functions/modules/app-problems/cases.js sideOf)

class ProblemCause {
  const ProblemCause(this.side, this.cause);
  final String side, cause;

  bool get user => side == 'user';
  @override
  String toString() => '$side/$cause';
}

/// What the device knows when the problem happens.
class DeviceState {
  const DeviceState({this.network = '', this.slowInternet = false});

  /// 'wifi', 'mobile', 'ethernet', 'none' or '' (not known).
  final String network;

  /// Most recent server calls took long (the internet, not one call).
  final bool slowInternet;

  bool get offline => network == 'none';
}

/// The causes the person can fix, each with its one-tap fix (lib/ui/ai_support_box.dart).
const userCauses = {
  'offline', 'slow_internet', 'location_off', 'location_denied', 'permission_denied', 'photo_too_big', 'session_expired', 'missing_field',
  'wrong_code', 'code_expired', 'too_many_tries', 'google_closed',
};

/// The cause of a failed server call [code] (Firebase Functions error codes) for the call [name].
ProblemCause causeOfCall(String name, String code, String message, DeviceState d) {
  final m = message.toLowerCase();
  if (d.offline || code == 'unavailable' && d.network == 'none') return const ProblemCause('user', 'offline');
  switch (code) {
    case 'unauthenticated':
      return const ProblemCause('user', 'session_expired');
    case 'resource-exhausted':
      return const ProblemCause('user', 'too_many_tries');
    case 'deadline-exceeded':
      if (m.contains('expired')) return const ProblemCause('user', 'code_expired');
      return d.slowInternet ? const ProblemCause('user', 'slow_internet') : const ProblemCause('our', 'server_slow');
    case 'invalid-argument':
    case 'failed-precondition':
    case 'already-exists':
    case 'out-of-range':
      if (m.contains('wrong code') || m.contains('6-digit')) return const ProblemCause('user', 'wrong_code');
      if (m.contains('expired')) return const ProblemCause('user', 'code_expired');
      if (m.contains('sign in') || m.contains('log in') || m.contains('login again')) return const ProblemCause('user', 'session_expired');
      if (m.contains('too big') || m.contains('too large') || m.contains(' kb') || m.contains(' mb')) return const ProblemCause('user', 'photo_too_big');
      return const ProblemCause('user', 'missing_field');
    case 'permission-denied':
      // "Sign in again" from the role checks is the session; anything else is a rule our code broke.
      return m.contains('sign in') ? const ProblemCause('user', 'session_expired') : const ProblemCause('our', 'server_refused');
    case 'unavailable':
      return d.slowInternet ? const ProblemCause('user', 'slow_internet') : const ProblemCause('our', 'server_down');
    default:
      return const ProblemCause('our', 'server_error');
  }
}

/// The cause of a key failure reported by the app ([kind] of lib/services/app_monitoring.dart) with its [message].
ProblemCause causeOf(String kind, String message, DeviceState d) {
  final m = message.toLowerCase();
  if (d.offline && kind != 'crash' && kind != 'freeze') return const ProblemCause('user', 'offline');
  switch (kind) {
    case 'location':
      if (m.contains('services are off') || m.contains('service')) return const ProblemCause('user', 'location_off');
      return const ProblemCause('user', 'location_denied');
    case 'upload':
      if (m.contains('unauthorized') || m.contains('unauthenticated')) return const ProblemCause('user', 'session_expired');
      if (m.contains('too big') || m.contains('too large') || m.contains('exceed')) return const ProblemCause('user', 'photo_too_big');
      if (m.contains('network') || m.contains('retry-limit')) return ProblemCause('user', d.slowInternet ? 'slow_internet' : 'offline');
      return const ProblemCause('our', 'upload_failed');
    case 'login':
    case 'otp':
    case 'email':
      if (m.contains('popup-closed') || m.contains('canceled') || m.contains('cancelled') || m.contains('popup_closed')) {
        return const ProblemCause('user', 'google_closed');
      }
      if (m.contains('network-request-failed') || m.contains('network')) return ProblemCause('user', d.slowInternet ? 'slow_internet' : 'offline');
      if (m.contains('wrong-password') || m.contains('invalid-credential') || m.contains('wrong code')) return const ProblemCause('user', 'wrong_code');
      if (m.contains('too-many-requests')) return const ProblemCause('user', 'too_many_tries');
      if (m.contains('expired')) return const ProblemCause('user', 'code_expired');
      if (m.contains('requires-recent-login') || m.contains('user-token-expired')) return const ProblemCause('user', 'session_expired');
      return const ProblemCause('our', 'sign_in_failed');
    case 'permission':
      return const ProblemCause('user', 'permission_denied');
    case 'slow':
      return d.slowInternet ? const ProblemCause('user', 'slow_internet') : const ProblemCause('our', 'slow');
    case 'tap':
      return const ProblemCause('our', 'no_response');
    case 'freeze':
      return const ProblemCause('our', 'hang');
    case 'stuck':
      return d.slowInternet ? const ProblemCause('user', 'slow_internet') : const ProblemCause('our', 'stuck_loading');
    case 'repeat':
      return const ProblemCause('our', 'repeat_fail');
    case 'crash':
      return const ProblemCause('our', 'crash');
    default:
      return const ProblemCause('our', 'error');
  }
}

/// Whether the AI Support box opens for this case. Every case is recorded either way. The box opens for our-side and device-side
/// problems the person met, and for the user-side causes they can fix; a plain missing field or wrong code opens it only when it
/// happens again (the form already shows its own message the first time). Uncaught code errors that the person may not even see
/// (a picture that did not load, a layout warning) never open it.
bool opensSupportBox(String kind, ProblemCause c, {required int times}) {
  if (kind == 'error' || kind == 'crash') return false;
  if (kind == 'slow' && c.cause == 'slow' && times < 2) return false;
  if (!c.user) return true;
  if (c.cause == 'google_closed') return false;
  if (const {'missing_field', 'wrong_code', 'too_many_tries', 'code_expired'}.contains(c.cause)) return times >= 2;
  return true;
}

/// Taps that are normally repeated on purpose (a quantity +/-, next / previous, back): never "no answer".
bool isRepeatTapOption(String label) {
  final l = label.trim().toLowerCase();
  if (l.isEmpty) return false;
  return RegExp(r'^[+\-−–]$|^\d+$|\b(add|remove|increase|decrease|next|previous|prev|back|more|less|plus|minus|scroll|swipe)\b').hasMatch(l);
}
