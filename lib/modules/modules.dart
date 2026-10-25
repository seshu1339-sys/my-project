import 'home_module.dart';
import 'services/services_module.dart';
import 'transport/transport_module.dart';

/// The home-page modules, in the order of their boxes under Today's Offers. The only place that knows all of them.
const homeModules = <HomeModule>[transportModule, servicesModule];
