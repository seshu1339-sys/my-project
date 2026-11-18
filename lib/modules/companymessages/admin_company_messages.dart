import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../home_module.dart';
import 'compose_page.dart';

/// Admin > Vendors & Shops > Vendor Messages (cost cuts part 5): the compose page with every type and target, the log and the staff
/// who may send. Listed in lib/modules/module_admin.dart.
const companyMessagesAdminSection = ModuleAdminSection(
  id: 'companyMessages',
  title: 'Vendor Messages',
  icon: Icons.campaign_outlined,
  hint: 'Official LOCAMARKET Team messages to vendors: all, a town, a category or Vendor IDs; who read them',
  build: _build,
);

Widget _build(Store store) => CompanyComposePage(store: store);
