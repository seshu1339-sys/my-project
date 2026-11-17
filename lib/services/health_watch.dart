import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../domain/health_status.dart';

/// The admin panel's view of the health status (owner spec H): one listener on healthStatus/current, one on the new "Report a problem"
/// messages and one on the open burst alerts (AI Agent + Health System part 1: the red banner), shared by the red marks, the top-bar
/// Health badge, the banner and the command box. Only in the live admin panel; in the demo studio and the tests it stays empty unless a
/// test sets [status] / [alerts].
class HealthWatch extends ChangeNotifier {
  HealthWatch._();
  static final instance = HealthWatch._();

  HealthStatus status = HealthStatus.empty;
  int newReports = 0;
  List<HealthAlert> alerts = const [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _status;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reports;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alerts;

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
    _alerts = store.firestore.collection('healthAlerts').where('open', isEqualTo: true).limit(20).snapshots().listen((q) {
      alerts = [for (final d in q.docs) HealthAlert.from(d.id, d.data())]..sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
      notifyListeners();
    }, onError: (_) {});
  }

  /// Closes one alert (the banner's "Close"); the rules allow only open: false with the admin's own uid.
  Future<void> close(Store store, String id) async {
    alerts = [for (final a in alerts) if (a.id != id) a];
    notifyListeners();
    if (!store.live) return;
    await store.firestore.collection('healthAlerts').doc(id).update({'open': false, 'closedBy': FirebaseAuth.instance.currentUser?.uid ?? '', 'closedAt': FieldValue.serverTimestamp()});
  }

  int get alertCount => status.failing.length + (status.serverErrors.isEmpty ? 0 : 1) + (newReports > 0 ? 1 : 0) + alerts.length;

  @visibleForTesting
  void set(HealthStatus s, {int reports = 0, List<HealthAlert> alerts = const []}) {
    status = s;
    newReports = reports;
    this.alerts = alerts;
    notifyListeners();
  }

  /// Stops listening (sign out).
  void stop() {
    _status?.cancel();
    _reports?.cancel();
    _alerts?.cancel();
    _status = null;
    _reports = null;
    _alerts = null;
    status = HealthStatus.empty;
    newReports = 0;
    alerts = const [];
  }
}
