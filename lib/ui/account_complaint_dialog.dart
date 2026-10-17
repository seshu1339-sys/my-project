import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/store.dart';
import 'shared.dart';

/// Lets a signed-in customer open a complaint against one of their recent
/// orders — the server requires a complaint to reference an order, so this
/// loads up to 30 recent ones and lets the customer pick. [run] is
/// AccountPage's own busy/error-handling wrapper, passed through so the
/// submit action still drives AccountPage's busy indicator exactly as
/// before. Extracted out of account.dart so the account shell stays a thin
/// composition root; behavior is unchanged from the original inline version.
Future<void> showComplaintDialog(
  BuildContext context,
  Store store,
  Future<void> Function(Future<void> Function()) run,
) async {
  // The server requires a complaint to reference an order, so the customer picks one.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs;
  try {
    orderDocs =
        (await FirebaseFirestore.instance
                .collection('orders')
                .where('userId', isEqualTo: store.user!.uid)
                .limit(30)
                .get())
            .docs;
  } catch (_) {
    if (context.mounted) {
      message(context, 'Your orders could not load. Please try again.');
    }
    return;
  }
  if (orderDocs.isEmpty) {
    if (context.mounted) {
      message(
        context,
        'Place an order first, then you can open a complaint about it.',
      );
    }
    return;
  }
  var orderId = orderDocs.first.id;
  if (!context.mounted) return;
  final subject = TextEditingController(),
      description = TextEditingController();
  final submit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Open a complaint'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: orderId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Order'),
              items: [
                for (final order in orderDocs)
                  DropdownMenuItem(
                    value: order.id,
                    child: Text(
                      'Order ${order.id.substring(0, 8)} • ${order.data()['status'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) orderId = value;
              },
            ),
            TextField(
              controller: subject,
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            TextField(
              controller: description,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'What happened?'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Submit'),
        ),
      ],
    ),
  );
  if (submit != true) {
    subject.dispose();
    description.dispose();
    return;
  }
  await run(() async {
    await store.createComplaint(
      orderId: orderId,
      subject: subject.text,
      description: description.text,
    );
    if (context.mounted) {
      message(
        context,
        'Complaint submitted. You can follow its full history here.',
      );
    }
  });
  subject.dispose();
  description.dispose();
}
