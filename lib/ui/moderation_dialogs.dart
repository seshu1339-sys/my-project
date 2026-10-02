import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Shared confirmation dialogs and widgets for the new Vendor/Staff detail
/// pages (admin_search.dart's result pages). Written fresh rather than
/// imported from vendor_moderation.dart/field_moderation.dart so those
/// existing, working files stay completely unchanged; any duplication with
/// those two specifically is intentional. vendor_detail_page.dart and
/// staff_detail_page.dart both use the one ApplicationPhoto widget below
/// instead of each defining their own copy.

/// Suspend/reinstate confirmation. When suspending, a reason of at least 3
/// characters is required (mirrors the existing vendor/field-staff dialogs).
/// Returns the trimmed reason to send to the server, or null if the admin
/// cancelled.
Future<String?> showSuspensionDialog(
  BuildContext context, {
  required String name,
  required bool suspend,
  required String suspendBody,
  required String reinstateBody,
}) async {
  final reason = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(suspend ? 'Suspend $name?' : 'Reinstate $name?'),
        content: suspend
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(suspendBody),
                TextField(
                  controller: reason,
                  maxLines: 3,
                  maxLength: 500,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(labelText: 'Reason for suspension (required)'),
                ),
              ])
            : Text(reinstateBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: suspend && reason.text.trim().length < 3 ? null : () => Navigator.pop(dialog, true),
            child: Text(suspend ? 'Suspend' : 'Reinstate'),
          ),
        ],
      ),
    ),
  );
  final note = reason.text.trim();
  reason.dispose();
  return go == true ? note : null;
}

/// Special Category Exclusives on/off + maximum duration, for one vendor.
/// Returns the chosen state, or null if the admin cancelled or entered an
/// invalid duration.
Future<({bool enabled, int? maxDurationDays})?> showExclusivesDialog(
  BuildContext context, {
  required String name,
  required bool currentlyEnabled,
  int? currentMaxDays,
}) async {
  var enabled = currentlyEnabled;
  final maxDays = TextEditingController(text: '${currentMaxDays ?? 30}');
  final go = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Special Category Exclusives — $name'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('When enabled, this vendor can publish its own one-off design/product entries immediately, with no separate review per item.'),
          SwitchListTile(
            title: const Text('Enabled for this vendor'),
            value: enabled,
            onChanged: (value) => setDialogState(() => enabled = value),
          ),
          if (enabled)
            TextField(
              controller: maxDays,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Maximum active duration per item (days)'),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  final days = int.tryParse(maxDays.text.trim());
  maxDays.dispose();
  if (go != true) return null;
  if (enabled && (days == null || days < 1)) return null;
  return (enabled: enabled, maxDurationDays: enabled ? days : null);
}

/// One private Storage photo, fetched with the admin's own access and shown
/// at a fixed preview size with a labeled caption underneath. Mirrors
/// admin.dart's _ApplicationPhoto / field_moderation.dart's _FieldPhoto
/// exactly, but is shared (not re-copied a third and fourth time) between
/// vendor_detail_page.dart and staff_detail_page.dart specifically, since
/// those two files are new and meant to share with each other.
class ApplicationPhoto extends StatelessWidget {
  const ApplicationPhoto({super.key, required this.label, required this.path});
  final String label;
  final String? path;
  @override
  Widget build(BuildContext context) {
    if (path == null || path!.isEmpty) {
      return SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 120, width: 160, alignment: Alignment.center, color: Colors.black12, child: const Text('No photo')),
        const SizedBox(height: 4),
        Text(label),
      ]));
    }
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path!).getDownloadURL(),
      builder: (context, snapshot) {
        Widget image;
        if (snapshot.hasError) {
          image = Container(height: 120, width: 160, alignment: Alignment.center, color: Colors.black12, child: const Text('Photo could not load'));
        } else if (!snapshot.hasData) {
          image = const SizedBox(height: 120, width: 160, child: Center(child: CircularProgressIndicator()));
        } else {
          final url = snapshot.data!;
          image = Semantics(button: true, label: 'View $label full size', child: InkWell(
            onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url)))),
            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, height: 120, width: 160, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(height: 120, width: 160, alignment: Alignment.center, color: Colors.black12, child: const Text('Photo could not load')))),
          ));
        }
        return SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [image, const SizedBox(height: 4), Text(label)]));
      },
    );
  }
}
