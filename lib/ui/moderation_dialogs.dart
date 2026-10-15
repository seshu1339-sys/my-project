import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Shared confirmation dialogs, widgets, and action-running helper for every
/// admin moderation page (vendor/field/complaint moderation, the vendor/staff
/// detail pages, admin search). The canonical implementation of the
/// suspend/reinstate dialog, the exclusives dialog, and the photo-preview
/// widget — vendor_moderation.dart and field_moderation.dart call into these
/// rather than keeping their own copies.

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
/// Returns the chosen state, or null if the admin cancelled. The Save button
/// is disabled (not a silent close) while enabled and the duration is
/// invalid, so the admin gets immediate feedback instead of the dialog just
/// vanishing with no explanation.
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
      builder: (context, setDialogState) {
        final days = int.tryParse(maxDays.text.trim());
        final invalid = enabled && (days == null || days < 1);
        return AlertDialog(
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
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'Maximum active duration per item (days)',
                  errorText: invalid ? 'Enter a maximum duration of 1 day or more.' : null,
                ),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: invalid ? null : () => Navigator.pop(dialog, true), child: const Text('Save')),
          ],
        );
      },
    ),
  );
  final days = int.tryParse(maxDays.text.trim());
  maxDays.dispose();
  if (go != true) return null;
  return (enabled: enabled, maxDurationDays: enabled ? days : null);
}

/// One private Storage photo, fetched with the admin's own access and shown
/// at the given preview size, with an optional caption underneath (omit
/// [label] to suppress it — used where photos are shown in a plain row with
/// no per-photo caption). The single implementation behind every admin
/// moderation page's photo preview.
class ApplicationPhoto extends StatelessWidget {
  const ApplicationPhoto({super.key, this.label, required this.path, this.height = 120, this.width = 160});
  final String? label;
  final String? path;
  final double height;
  final double width;
  @override
  Widget build(BuildContext context) {
    final caption = label == null ? const <Widget>[] : [const SizedBox(height: 4), Text(label!)];
    if (path == null || path!.isEmpty) {
      return SizedBox(width: width, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: height, width: width, alignment: Alignment.center, color: Colors.black12, child: const Text('No photo')),
        ...caption,
      ]));
    }
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path!).getDownloadURL(),
      builder: (context, snapshot) {
        Widget image;
        if (snapshot.hasError) {
          image = Container(height: height, width: width, alignment: Alignment.center, color: Colors.black12, child: const Text('Photo could not load'));
        } else if (!snapshot.hasData) {
          image = SizedBox(height: height, width: width, child: const Center(child: CircularProgressIndicator()));
        } else {
          final url = snapshot.data!;
          image = Semantics(button: true, label: 'View ${label ?? 'photo'} full size', child: InkWell(
            onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url)))),
            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, height: height, width: width, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(height: height, width: width, alignment: Alignment.center, color: Colors.black12, child: const Text('Photo could not load')))),
          ));
        }
        return SizedBox(width: width, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [image, ...caption]));
      },
    );
  }
}

/// Runs [action] (almost always `() => store.call(name, data)`), shows the
/// SnackBar text [onSuccess] produces from the result when it completes (or
/// the fixed text 'Saved' if [onSuccess] is omitted), or shows the error's
/// own `toString()` verbatim — exactly as every moderation page's hand-rolled
/// `catch (e) { ... Text('$e') ... }` already did, so switching a call site
/// to this helper changes no visible text on the failure path. Takes a
/// closure rather than (name, data) so it has zero dependency on Store or
/// Firebase and can be driven by a fake in a test with no mocking at all.
Future<void> runModerationAction(
  BuildContext context,
  Future<Map<String, dynamic>> Function() action, {
  String Function(Map<String, dynamic> result)? onSuccess,
}) async {
  try {
    final result = await action();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(onSuccess?.call(result) ?? 'Saved')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
