// Photo limits module (owner, 6 Nov 2026): one shop photo for every vendor (not counted), 2 extra photos free, the paid plan's number
// otherwise; extra shop photos and own item photos share them; when a paid plan ends only the first 2 stay (functions/modules/photo-limits).
// The vendor app gets the allowance and the item photos section; the admin panel gets admin_item_photos.dart (through module_admin.dart).
export 'item_photos_section.dart';
export 'photo_allowance.dart';

const photolimitsRoute = '/item-photos';
