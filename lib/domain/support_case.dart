import 'dart:ui' show Rect;

import 'problem_cause.dart';

/// One problem a person just met (AI Agent + Health System parts 2-3): what the AI Support box shows and what goes to the server.
class SupportCase {
  const SupportCase({required this.kind, required this.message, required this.cause, this.option = '', this.screen = '', this.rect, this.fingerprint = ''});

  /// The kind of lib/services/app_monitoring.dart (login, otp, upload, tap, freeze, stuck, slow, repeat, api…).
  final String kind;

  /// What happened, cleaned (no emails, links or long numbers).
  final String message;
  final ProblemCause cause;

  /// The option (button) the person used, when known: "Save item".
  final String option;
  final String screen;

  /// Where that option is on the screen (global), to highlight it.
  final Rect? rect;

  /// The same problem has the same fingerprint everywhere (the box opens once per fingerprint in a session).
  final String fingerprint;

  bool get userSide => cause.user;
}
