import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../domain/health_status.dart';

/// The admin panel's view of the health status (owner spec H): one listener on healthStatus/current and one on the new "Report a
/// problem" messages, shared by the red marks, the top-bar Health badge and the command box. Only in the live admin panel; in the demo
/// studio and the tests it stays empty unless a test sets [status].
class HealthWatch extends ChangeNotifier {
  HealthWatch._();
  static final instance = HealthWatch._();

  HealthStatus status = HealthStatus.empty;
  int newReports = 0;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _status;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reports;

  /// Starts listening (once). Two small listeners: one document, and at most 50 new reports.
  void start(Store store) {
    if (!store.live || _status != null) return;
    try {
      _listen(store);
    } catch (_) {
      // Firebase not started (tests, a broken start): the marks just stay empty.
    }
  }

  void _listen(Store store) {
    _status = store.firestore.collection('healthStatus').doc('current').snapshots().listen((d) {
      status = HealthStatus.from(d.data());
      notifyListeners();
    }, onError: (_) {});
    _reports = store.firestore.collection('problemReports').where('status', isEqualTo: 'new').limit(50).snapshots().listen((q) {
      newReports = q.size;
      notifyListeners();
    }, onError: (_) {});
  }

  int get alertCount => status.failing.length + (status.serverErrors.isEmpty ? 0 : 1) + (newReports > 0 ? 1 : 0);

  @visibleForTesting
  void set(HealthStatus s, {int reports = 0}) {
    status = s;
    newReports = reports;
    notifyListeners();
  }

  /// Stops listening (sign out).
  void stop() {
    _status?.cancel();
    _reports?.cancel();
    _status = null;
    _reports = null;
    status = HealthStatus.empty;
    newReports = 0;
  }
}
