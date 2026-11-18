// Camera search labels (cost cuts part 1, 18 Nov 2026): Google ML Kit image labeling on the phone (free, offline). The photo stays
// on the phone; only the names come back. The website has no camera search (owner, 18 Nov 2026), so its build gets the stub.
import '../domain/camera_search.dart';
import 'camera_labeler_stub.dart' if (dart.library.io) 'camera_labeler_mlkit.dart' as impl;

/// Names what is in the photo at [path] (most sure first). Throws when the phone cannot label photos.
typedef CameraLabeler = Future<List<CameraLabel>> Function(String path);

Future<List<CameraLabel>> labelPhotoOnPhone(String path) => impl.labelPhoto(path);
