import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import 'staff_link_model.dart';

/// Admin: who registered this vendor or provider: "Registered by STF-NRPM-116-482 (Kiran) on 06/11/2026", or "Self-registered (no
/// staff link)". The admin can remove a wrong link.
class RegisteredByLine extends StatelessWidget {
  const RegisteredByLine({super.key, required this.store, required this.accountUid, this.provider = false});
  final Store store;
  final String accountUid;
  final bool provider;

  @override
  Widget build(BuildContext context) {
    if (!store.live) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: store.firestore.collection('staffLinks').doc(staffLinkId(provider ? 'provider' : 'vendor', accountUid)).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data?.data();
        return RegisteredByView(link: data == null ? null : StaffLink.fromData(snapshot.data!.id, data), onRemove: (link) => store.call('removeStaffLink', {'linkId': link.id}));
      },
    );
  }
}

class RegisteredByView extends StatelessWidget {
  const RegisteredByView({super.key, required this.link, this.onRemove});
  final StaffLink? link;
  final Future<void> Function(StaffLink link)? onRemove;

  Future<void> _remove(BuildContext context, StaffLink link) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove this staff link?'),
        content: Text('${link.name.isEmpty ? link.code : link.name} will no longer show as registered by ${link.staffCode}. Nothing else changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('registered-by-remove-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await onRemove!(link);
      messenger.showSnackBar(const SnackBar(content: Text('Link removed')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = link;
    if (l == null) return const Text('Self-registered (no staff link)', key: ValueKey('registered-by-self'));
    final staff = [l.staffCode, if (l.staffName.isNotEmpty) '(${l.staffName})'].join(' ');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          'Registered by $staff${l.linkedAt == null ? '' : ' on ${linkDate(l.linkedAt)}'}',
          key: const ValueKey('registered-by-staff'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (onRemove != null) TextButton(key: const ValueKey('registered-by-remove'), onPressed: () => _remove(context, l), child: const Text('Remove link')),
      ],
    );
  }
}
