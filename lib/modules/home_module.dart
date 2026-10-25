import 'package:flutter/material.dart';

import '../data/store.dart';

/// What a home-page module (Transport, Services, ...) tells the rest of the app about itself. A module lives in its own folder
/// (`lib/modules/<id>/`), has its own route name and its own data collection, and imports nothing from another module, nor from
/// Shops, Promotions or the other home sections (test/module_independence_test.dart enforces this). The home page and the admin
/// panel only read the list in modules.dart, so removing or changing one module is one line there plus its folder.
class HomeModule {
  const HomeModule({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.route,
    required this.open,
    this.collection = '',
    this.admin,
    this.adminHint = '',
  });

  /// Short lower-case name: 'transport', 'services'.
  final String id;

  /// The name on the home box and as the page title.
  final String title;
  final IconData icon;

  /// The box colour on the home page.
  final Color color;

  /// The module's own route name, e.g. '/transport'.
  final String route;

  /// The module's own Firestore collection ('' when it keeps its data elsewhere, see its module file).
  final String collection;

  /// Opens the module's page.
  final void Function(BuildContext context, Store store) open;

  /// The module's own section in the admin panel (Settings), if it has one.
  final Widget Function(Store store)? admin;
  final String adminHint;
}
