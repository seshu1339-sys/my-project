import 'home_module.dart';
import 'plans/admin_plans.dart';
import 'transport/admin_transport.dart';

/// The admin sections of the home modules (Settings), in this order. Only the admin panel imports this list.
const moduleAdminSections = <ModuleAdminSection>[transportAdminSection];

/// The modules with their own main tab in the admin panel, in this order, between Promotions and Settings.
const moduleAdminTabs = <ModuleAdminSection>[plansAdminSection];
