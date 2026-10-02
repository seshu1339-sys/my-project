import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'store.dart';

/// Every Storage upload path `Store` exposes — one admin catalog-image
/// uploader and three role-specific private-photo uploaders (vendor
/// application, vendor shop photo, field-staff item photo). Defined as
/// extension methods so every call site (`store.upload(...)`,
/// `store.uploadShopPhoto(...)`, etc. across admin.dart/vendor.dart/
/// field.dart) is unchanged — Dart calls an extension method identically to
/// an instance method.
extension StoreUploads on Store {
  /// Uploads to [folder] (admin catalog by default; a vendor passes its own
  /// approved-vendor folder) and returns the public download URL.
  Future<String> upload(XFile file, {String folder = 'catalog'}) async {
    final image = await _readImage(this, file);
    final ref = FirebaseStorage.instance.ref(
      '$folder/${DateTime.now().microsecondsSinceEpoch}.${image.ext}',
    );
    await ref.putData(image.bytes, SettableMetadata(contentType: image.type));
    return ref.getDownloadURL();
  }

  /// Stores one of the two mandatory vendor-application photos at its own fixed
  /// private path ([kind] is 'vendorPhoto' or 'shopPhoto') and returns the bytes.
  Future<Uint8List> uploadApplicationPhoto(String kind, XFile file) async {
    if (kind != 'vendorPhoto' && kind != 'shopPhoto') {
      throw ArgumentError('Unknown application photo.');
    }
    final uid = user?.uid;
    if (uid == null) throw StateError('Sign in first.');
    final image = await _readImage(this, file);
    await FirebaseStorage.instance
        .ref('vendorApplications/$uid/$kind')
        .putData(image.bytes, SettableMetadata(contentType: image.type));
    return image.bytes;
  }

  /// Stores the field-staff member's own mandatory registration photo at its
  /// fixed path (mirrors uploadApplicationPhoto's 'vendorPhoto' exactly, one
  /// level up at fieldStaffApplications/{uid}/staffPhoto instead, since staff
  /// have no separate "shop photo" to also store here).
  Future<Uint8List> uploadStaffPhoto(XFile file) async {
    final uid = user?.uid;
    if (uid == null) throw StateError('Sign in first.');
    final image = await _readImage(this, file);
    await FirebaseStorage.instance
        .ref('fieldStaffApplications/$uid/staffPhoto')
        .putData(image.bytes, SettableMetadata(contentType: image.type));
    return image.bytes;
  }

  /// Stores one of an approved vendor's shop photos at its fixed slot path
  /// ([slot] is 1-9; the admin-configurable settings/business.vendorPhotoLimit,
  /// default 2, is enforced server-side — this is only a client-side sanity
  /// bound matching the storage.rules ceiling). The caller still has to call
  /// the submitShopPhoto function afterwards so it goes to pending admin review.
  Future<Uint8List> uploadShopPhoto(int slot, XFile file) async {
    if (slot < 1 || slot > 9) throw ArgumentError('Shop photo slot must be from 1 to 9.');
    final uid = user?.uid;
    if (uid == null) throw StateError('Sign in first.');
    final image = await _readImage(this, file);
    await FirebaseStorage.instance
        .ref('vendorShopPhotos/$uid/shopPhoto$slot')
        .putData(image.bytes, SettableMetadata(contentType: image.type));
    return image.bytes;
  }

  /// Stores one of a field-staff item's photos at its own per-submission,
  /// per-index path (fieldSubmissions/$uid/${submissionId}_$index — not a
  /// fixed slot the way vendor photos are, since a submission id is already
  /// unique per visit). The admin-configurable settings/business.fieldPhotoLimit
  /// (default 2) is enforced server-side. The caller still has to call
  /// submitFieldEntry afterwards so it goes to pending admin review.
  Future<void> uploadFieldPhoto(String submissionId, int index, XFile file) async {
    final uid = user?.uid;
    if (uid == null) throw StateError('Sign in first.');
    final image = await _readImage(this, file);
    await FirebaseStorage.instance
        .ref('fieldSubmissions/$uid/${submissionId}_$index')
        .putData(image.bytes, SettableMetadata(contentType: image.type));
  }
}

// A plain top-level helper, not an extension method, because it only needs
// to read the public `store.live` field — and because Dart extension methods
// in a different file cannot call another file's *private* instance methods,
// this is the one piece of the original `Store._readImage` that has to take
// its receiver explicitly rather than staying "on Store".
Future<({Uint8List bytes, String ext, String type})> _readImage(Store store, XFile file) async {
  if (!store.live) {
    throw StateError(
      'Image uploads require a connected Firebase project. You can use an image URL in the demo.',
    );
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > 5 * 1024 * 1024) {
    throw StateError('Choose an image smaller than 5 MB.');
  }
  final ext = file.name.split('.').last.toLowerCase();
  final type = ext == 'png'
      ? 'image/png'
      : ext == 'webp'
      ? 'image/webp'
      : 'image/jpeg';
  return (bytes: bytes, ext: ext, type: type);
}
