import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'company_inbox.dart';
import 'compose_page.dart';

export 'company_inbox.dart' show CompanyBell, CompanyInboxPage;

/// The route of the vendors' inbox.
const companymessagesRoute = '/company-messages';

/// Company messages module (owner, 18 Nov 2026: cost cuts part 5): official "LOCAMARKET Team" messages to vendors, no AI, ₹0. Own
/// folder, own collections (functions/modules/company-messages); nothing else needs it. Removing its lines from the vendor app bar,
/// the staff app bar and module_admin.dart removes it; everything else keeps working.

/// The vendor app's bell (signed in, live only).
Widget? vendorCompanyBell(Store store) => store.live && store.user != null ? CompanyBell(store: store) : null;

/// The staff app's "Vendor Messages" button: only for staff the admin allowed (companyMessageSenders/main).
class StaffCompanyMessagesButton extends StatelessWidget {
  const StaffCompanyMessagesButton({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final uid = store.user?.uid;
    if (!store.live || uid == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('companyMessageSenders').doc('main').snapshots(),
      builder: (context, snap) {
        final allowed = (snap.data?.data()?['staff'] as List? ?? const []).whereType<Map>().any((s) => s['uid'] == uid);
        if (!allowed) return const SizedBox.shrink();
        return IconButton(
          key: const ValueKey('staff-company-messages'),
          tooltip: 'Vendor Messages',
          icon: const Icon(Icons.campaign_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(appBar: AppBar(title: const Text('Vendor Messages')), body: CompanyComposePage(store: store, staff: true)),
          )),
        );
      },
    );
  }
}
