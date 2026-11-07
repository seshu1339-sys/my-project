// Staff Area System module: towns with a radius, named areas (Free / Pending / Booked), one staff member each, claimed only while
// standing inside with GPS on and the Terms accepted; a daily target of Today's Offers per area (the staff member's plus the area's
// vendors' own), missed days and automatic deactivation (functions/modules/staff-areas). The staff app gets the claim page, the
// dashboard, the offer form and the Terms; the admin panel gets admin_staff_areas.dart (through module_admin.dart only).
// Automatic areas (owner, 7 Nov 2026): the staff member taps a centre, the server sets the radius from the building density.
// Own folder, own collections, and no import from another module.
export 'area_map.dart';
export 'area_picker_map.dart';
export 'auto_area.dart';
export 'staff_area_claim_page.dart';
export 'staff_area_dashboard.dart';
export 'staff_area_model.dart';
export 'staff_auto_area_page.dart';
export 'staff_offer_form.dart';
export 'staff_terms.dart';

const staffareasRoute = '/staff-areas';
