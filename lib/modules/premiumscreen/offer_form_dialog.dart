import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// A photo chosen in the form. The file is null only in tests.
class OfferPhoto {
  const OfferPhoto(this.file, this.bytes);
  final XFile? file;
  final Uint8List bytes;
}

/// Chooses a photo; the gallery unless a test gives another.
typedef PickOfferPhoto = Future<OfferPhoto?> Function();

/// What the vendor filled in.
class OfferFormResult {
  const OfferFormResult({required this.photo, required this.price, required this.hours});
  final OfferPhoto photo;
  final num price;
  final int hours;
}

/// The only things a vendor gives: a photo, a price and how long. Pops an [OfferFormResult], or null when cancelled.
class OfferFormDialog extends StatefulWidget {
  const OfferFormDialog({super.key, required this.hourOptions, this.pickPhoto});
  final List<int> hourOptions;
  final PickOfferPhoto? pickPhoto;

  @override
  State<OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<OfferFormDialog> {
  final formKey = GlobalKey<FormState>();
  final price = TextEditingController();
  OfferPhoto? photo;
  int? hours;
  String? error;

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  Future<OfferPhoto?> _gallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    return file == null ? null : OfferPhoto(file, await file.readAsBytes());
  }

  Future<void> _pick() async {
    try {
      final picked = await (widget.pickPhoto ?? _gallery)();
      if (picked != null && mounted) {
        setState(() {
          photo = picked;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void _send() {
    final ok = formKey.currentState!.validate();
    setState(() => error = photo == null ? 'Add a photo of the item' : hours == null ? 'Choose how long the offer runs' : null);
    if (!ok || error != null) return;
    Navigator.pop(context, OfferFormResult(photo: photo!, price: num.parse(price.text.trim()), hours: hours!));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text("Today's Offer"),
    content: SizedBox(
      width: 380,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: photo == null
                  ? OutlinedButton.icon(key: const ValueKey('todays-offer-photo'), onPressed: _pick, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add item photo'))
                  : InkWell(
                      key: const ValueKey('todays-offer-photo'),
                      onTap: _pick,
                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(photo!.bytes, height: 120, fit: BoxFit.cover)),
                    ),
            ),
            TextFormField(
              key: const ValueKey('todays-offer-price'),
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price (₹)'),
              validator: (v) => (num.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter a price above 0' : null,
            ),
            const SizedBox(height: 12),
            const Text('Run for'),
            Wrap(spacing: 8, children: [
              for (final option in widget.hourOptions)
                ChoiceChip(
                  key: ValueKey('todays-offer-hours-$option'),
                  label: Text('$option hours'),
                  selected: hours == option,
                  onSelected: (_) => setState(() => hours = option),
                ),
            ]),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, key: const ValueKey('todays-offer-error'), style: const TextStyle(color: Colors.red))),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('todays-offer-send'), onPressed: _send, child: const Text('Go live')),
    ],
  );
}
