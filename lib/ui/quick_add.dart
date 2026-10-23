// Quick Add Item for Staff and Vendors. This file only re-exports the parts (so every existing import keeps working); each part is its own
// file with its own widgets and state: core (types and helpers), entry (account gate + panel), shop (vendor shop setup, category),
// photo (photo area, place picker), item (one item), batch (up to 5 items), items (my items, tabs, photos).
export 'quick_add_core.dart';
export 'quick_add_entry.dart';
export 'quick_add_shop.dart';
export 'quick_add_photo.dart';
export 'quick_add_item.dart';
export 'quick_add_batch.dart';
export 'quick_add_items.dart';
