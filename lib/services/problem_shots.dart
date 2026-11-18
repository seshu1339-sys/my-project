import '../data/store.dart';

/// One problem screenshot as base64 ('' when it was deleted: solved, or older than 30 days).
/// Since 18 Nov 2026 (cost cuts part 3) every screenshot is a path in the US bucket (problems/..., reports/..., support/...), opened
/// only by the admin through the `problemShot` function (functions/problem-shots.js). An id without a slash is a record of the
/// version before ([oldCollection]: appShots or supportShots), read from Firestore until those old records are deleted.
Future<String> loadProblemShot(Store store, String ref, {String oldCollection = 'appShots'}) async {
  if (ref.isEmpty) return '';
  if (ref.contains('/')) {
    final r = await store.call('problemShot', {'path': ref});
    return '${r['data'] ?? ''}';
  }
  final d = (await store.firestore.collection(oldCollection).doc(ref).get()).data();
  return '${d?['data'] ?? ''}';
}

/// "5 people" or, past the 100 the record keeps, "100+ people".
String peopleText(int users, bool more) => more ? '$users+ people' : (users == 1 ? '1 person' : '$users people');
