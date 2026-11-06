import 'flash/admin_flash.dart';
import 'home_module.dart';
import 'offers/admin_offers.dart';
import 'payments/admin_payments.dart';
import 'plans/admin_plans.dart';
import 'photolimits/admin_item_photos.dart';
import 'premiumadmin/admin_premium.dart';
import 'staffareas/admin_staff_areas.dart';
import 'transport/admin_transport.dart';

/// The admin sections of the home modules (Settings), in this order. Only the admin panel imports this list.
const moduleAdminSections = <ModuleAdminSection>[transportAdminSection, itemPhotosAdminSection];

/// The modules with their own main tab in the admin panel, in this order, between Promotions and Settings.
const moduleAdminTabs = <ModuleAdminSection>[plansAdminSection, offersAdminSection, premiumAdminSection, paymentsAdminSection, flashAdminSection, staffAreasAdminSection];
