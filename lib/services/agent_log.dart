import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';

/// Every command-box action, logged (owner spec I, 17 Nov 2026): who, what, when. One small write per action, only by a signed-in
/// administrator (firestore.rules agentLog: create only, with the admin's own uid and the server's time; nobody edits or deletes it).
///   `agentLog/<auto>`  {uid, email, action, command, target, details, platform, at}
/// The admin reads it in the command box's menu ("Agent log"). Off line (demo studio) nothing is written.
class AgentLog {
  AgentLog._();

  /// Test seam: what was logged, when set.
  static List<Map<String, dynamic>>? testSink;

  static Future<void> write(Store store, {required String action, String command = '', String target = '', String platform = '', Map<String, Object?> details = const {}}) async {
    final row = <String, dynamic>{
      'action': action,
      'command': _clip(command, 300),
      'target': _clip(target, 200),
      'platform': platform,
      'details': {for (final e in details.entries) e.key: e.value is num || e.value is bool ? e.value : _clip('${e.value}', 300)},
    };
    if (testSink != null) {
      testSink!.add(row);
      return;
    }
    if (!store.live) return;
    final user = store.user;
    if (user == null) return;
    try {
      await store.firestore.collection('agentLog').add({...row, 'uid': user.uid, 'email': user.email ?? '', 'at': FieldValue.serverTimestamp()});
    } catch (_) {
      // A log that cannot be written never stops the admin's work.
    }
  }

  static String _clip(String s, int max) => s.length > max ? s.substring(0, max) : s;
}
