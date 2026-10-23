import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';

// Small tools every vendor section uses. A section owns its own state (its own text boxes, its own "busy" flag, its own streams) and only
// shares these stateless helpers, so one section can be changed, removed or broken without touching the others.

/// The card every vendor section is drawn in.
Widget vendorCard(String title, List<Widget> children, {String? note}) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      if (note != null) Text(note),
      ...children,
    ]),
  ),
);

/// What the vendor is told after sending a change: published at once by policy, or held for the administrator.
String vendorPublished(String status) => status == 'approved' ? 'Published' : 'Pending administrator approval';

Future<XFile?> vendorPickImage() => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);

/// Off by default: existing free-upload behaviour is preserved until the admin has populated the Product Image Library and explicitly turns
/// this on.
bool vendorLibraryEnforced(Store store) => store.business.text('productImageLibraryEnforced', 'false').trim().toLowerCase() == 'true';

/// Lets the vendor pick an already-approved image instead of uploading its own; the same image URL is reused across every product that picks
/// it (no duplicate file per vendor).
Future<Entry?> pickLibraryImage(BuildContext context, Store store) {
  final images = store.entries('productImageLibrary').where((e) => e.active).toList();
  return showDialog<Entry>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Choose a product image'),
      content: SizedBox(
        width: 420,
        child: images.isEmpty
            ? const Text('No approved images are available yet. Ask the administrator to add some to the Product Image Library.')
            : SingleChildScrollView(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final img in images)
                    Semantics(
                      button: true,
                      label: 'Choose ${img.text('name', img.id)}',
                      child: InkWell(
                        onTap: () => Navigator.pop(dialog, img),
                        child: SizedBox(
                          width: 110,
                          child: Column(children: [
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(img.text('imageUrl'), width: 100, height: 100, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined))),
                            Text(img.text('name', img.id), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel'))],
    ),
  );
}

/// Asks for one number in a small dialog; null when cancelled. Throws a [StateError] with a plain message for an invalid entry.
Future<num?> askVendorNumber(BuildContext context, String title, String label, {required bool integer, String initial = ''}) async {
  final text = await showDialog<String>(context: context, builder: (_) => _NumberDialog(title: title, label: label, initial: initial));
  if (text == null) return null;
  final parsed = integer ? int.tryParse(text.trim()) : double.tryParse(text.trim());
  if (parsed == null || parsed < 0) throw StateError(integer ? 'Enter a whole number.' : 'Enter a valid number.');
  return parsed;
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.label, required this.initial});
  final String title, label, initial;
  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: controller, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: widget.label)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
    ],
  );
}

/// What each vendor section's state class adds: its OWN busy flag (one section working never greys out another), a message, and a runner
/// that shows an error as a message instead of failing.
mixin VendorSectionState<T extends StatefulWidget> on State<T> {
  bool busy = false;

  void toast(Object message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      toast(e);
    }
    if (mounted) setState(() => busy = false);
  }
}
