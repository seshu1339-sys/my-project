// Staff Links module: vendors and service providers register themselves in the vendor app; a staff member links one by their ID
// within 30 minutes of the registration (functions/modules/staff-links). The staff app gets the link page and a read-only list; the
// admin panel gets "Registered by". Own folder, own collection (staffLinks), and no import from another module.
export 'registered_by.dart';
export 'staff_link_model.dart';
export 'staff_link_page.dart';
export 'staff_linked_list.dart';

const stafflinksRoute = '/staff-links';
