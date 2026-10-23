import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/store.dart';
import '../domain/places.dart';
import 'quick_add_core.dart';

/// Photo area with Camera / Gallery buttons -- shared by the single and the batch form.
class QuickPhotoArea extends StatelessWidget {
  const QuickPhotoArea({super.key, required this.bytes, required this.busy, required this.onPick, this.height = 200, this.suffix = ''});
  final Uint8List? bytes;
  final bool busy;
  final void Function(ImageSource source) onPick;
  final double height;
  final String suffix;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        height: height,
        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Image.memory(bytes!, key: ValueKey('quick-photo-preview$suffix'), fit: BoxFit.cover)
            : Center(child: busy ? const CircularProgressIndicator() : const Icon(Icons.image_outlined, size: 56)),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton.icon(
              key: ValueKey('quick-camera$suffix'),
              onPressed: busy ? null : () => onPick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Camera', style: TextStyle(fontSize: 18)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              key: ValueKey('quick-gallery$suffix'),
              onPressed: busy ? null : () => onPick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery', style: TextStyle(fontSize: 18)),
            ),
          ),
        ),
      ]),
    ],
  );
}

Future<QuickPhotoResult?> quickDefaultPick(Store store, ImageSource source) async {
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
  if (file == null) return null;
  final id = '${DateTime.now().microsecondsSinceEpoch}';
  final bytes = await store.uploadQuickPhoto(id, file);
  return QuickPhotoResult(id, bytes);
}

/// Staff: search any town of the pincode directory (or one of the admin's extra places).
Future<QuickPlace?> showQuickPlacePicker(BuildContext context, Store store, QuickEnv env) {
  final text = TextEditingController();
  var results = <Place>[];
  return showDialog<QuickPlace>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: const Text('Choose the town'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('quick-place-search'),
                controller: text,
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search town or pincode', border: OutlineInputBorder()),
                onChanged: (value) async {
                  final index = await env.places();
                  setState(() => results = index.search(value, limit: 10));
                },
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final place in results)
                      ListTile(
                        key: ValueKey('quick-place-${place.pincode}-${place.name}'),
                        title: Text(place.label),
                        subtitle: Text(place.subtitle),
                        onTap: () => Navigator.pop(dialog, QuickPlace.fromPlace(place)),
                      ),
                    if (text.text.trim().isEmpty)
                      for (final extra in store.quickLocations)
                        ListTile(
                          key: ValueKey('quick-extra-${extra.id}'),
                          leading: const Icon(Icons.place_outlined),
                          title: Text(extra.text('name', extra.id)),
                          onTap: () => Navigator.pop(dialog, QuickPlace.fromEntry(extra)),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel'))],
      ),
    ),
  );
}
