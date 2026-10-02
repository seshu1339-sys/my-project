import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';

/// Returns every reason the registration must not be submitted yet. Mirrors
/// the server-side checks in functions/domain.js's fieldStaffDetails(), the
/// same way vendorApplicationErrors() mirrors vendorApplication().
List<String> fieldStaffRegistrationErrors({
  required String name,
  required String phone,
  required bool hasPhoto,
}) {
  bool between(String v, int min, int max) => v.trim().length >= min && v.trim().length <= max;
  return [
    if (!between(name, 2, 100)) 'Enter your full name.',
    if (!RegExp(r'^\+?[0-9][0-9 -]{6,17}$').hasMatch(phone.trim())) 'Enter a valid contact phone number.',
    if (!hasPhoto) 'Upload a clear photo of yourself.',
  ];
}

/// Shown once, the first time a verified-email user opens the Field Assistant
/// app and no fieldStaff/{uid} doc exists yet. A photo is mandatory — the
/// server (requestFieldStaffAccess) independently refuses to create the
/// pending record without one, the same way vendor registration independently
/// refuses without its two mandatory photos.
class FieldRegistrationForm extends StatefulWidget {
  const FieldRegistrationForm({super.key, required this.store});
  final Store store;
  @override
  State<FieldRegistrationForm> createState() => _FieldRegistrationFormState();
}

class _FieldRegistrationFormState extends State<FieldRegistrationForm> {
  late final name = TextEditingController(text: widget.store.user?.displayName ?? '');
  final phone = TextEditingController();
  Uint8List? photoBytes;
  bool photoReady = false;
  bool uploading = false;
  bool busy = false;
  List<String> errors = const [];

  void toast(Object message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));

  Future<void> pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() => uploading = true);
      final bytes = await widget.store.uploadStaffPhoto(file);
      if (!mounted) return;
      setState(() { photoBytes = bytes; photoReady = true; errors = const []; });
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> submit() async {
    final problems = fieldStaffRegistrationErrors(name: name.text, phone: phone.text, hasPhoto: photoReady);
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      await widget.store.call('requestFieldStaffAccess', {
        'name': name.text.trim(),
        'phone': phone.text.trim(),
      });
    } catch (e) {
      if (mounted) toast(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Field staff registration', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Complete every field and upload a clear photo of yourself, then submit for administrator approval.'),
      const SizedBox(height: 16),
      TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your full name')),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone')),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your photo', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('A clear personal photo so the administrator can identify you.'),
        const SizedBox(height: 8),
        if (photoBytes != null)
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photoBytes!, height: 150, fit: BoxFit.cover))
        else
          Container(height: 90, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)), child: Icon(photoReady ? Icons.check_circle : Icons.add_a_photo_outlined)),
        const SizedBox(height: 8),
        Text(uploading ? 'Uploading...' : photoReady ? 'Photo uploaded' : 'Required: not uploaded yet'),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: busy || uploading ? null : () => pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose photo')),
          if (!kIsWeb) OutlinedButton.icon(onPressed: busy || uploading ? null : () => pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take photo')),
        ]),
      ]))),
      if (errors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Please fix the following before submitting:', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final e in errors) Text('• $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy || uploading ? null : submit, child: Text(busy ? 'Submitting...' : 'Submit for approval')),
    ]),
  ))));

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }
}
