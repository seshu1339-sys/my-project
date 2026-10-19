import '../data/store.dart';
import '../domain/catalog.dart';

/// The one Firestore doc (`settings/my_default`) that holds a full snapshot
/// of every layout/appearance doc the admin can edit -- every
/// `settings/section_*` doc plus `scrollingText` and `theme`. Reused as both
/// the save target and the restore source, so "my default" always means
/// exactly what was saved the last time `saveAsDefault` ran.
const myDefaultDocId = 'my_default';

/// Snapshots every current layout/appearance setting into one document, so
/// `resetToDefault` can restore exactly this state later. Overwrites any
/// previously saved default.
Future<void> saveAsDefault(Store store) async {
  final snapshot = <String, dynamic>{
    for (final entry in store.entries('settings'))
      if (entry.id.startsWith('section_') ||
          entry.id == 'scrollingText' ||
          entry.id == 'theme')
        entry.id: entry.data,
  };
  await store.save(
    'settings',
    Entry(myDefaultDocId, {
      'snapshot': snapshot,
      'savedAt': DateTime.now().toIso8601String(),
    }),
  );
}

/// Restores every layout/appearance doc to exactly what `saveAsDefault` last
/// captured. Throws a [StateError] (caught and shown to the admin by the
/// caller) if nothing has been saved yet.
Future<void> resetToDefault(Store store) async {
  final saved = store
      .entries('settings')
      .where((e) => e.id == myDefaultDocId)
      .firstOrNull;
  if (saved == null) {
    throw StateError(
      'No default saved yet. Use "Save as My Default" first.',
    );
  }
  final snapshot = saved.data['snapshot'];
  if (snapshot is! Map) {
    throw StateError('The saved default is corrupted and cannot be restored.');
  }
  for (final entry in snapshot.entries) {
    final data = entry.value;
    if (data is Map) {
      await store.save(
        'settings',
        Entry(entry.key as String, Map<String, dynamic>.from(data)),
      );
    }
  }
}
