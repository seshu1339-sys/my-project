import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'admin_premium_data.dart';

/// What the form returns: the fields to save, and a new photo still to upload (null keeps fields['photoUrl']).
class WholesaleDraft {
  const WholesaleDraft(this.fields, this.photo);
  final Map<String, dynamic> fields;
  final XFile? photo;
}

/// The admin's form for one wholesale offer. Pops a [WholesaleDraft], or null when cancelled.
class WholesaleFormDialog extends StatefulWidget {
  const WholesaleFormDialog({super.key, this.offer, required this.now, this.pickPhoto, this.pickDate});
  final AdminWholesale? offer;
  final DateTime now;

  /// Chooses a photo or a date; the normal pickers unless a test gives others.
  final Future<XFile?> Function()? pickPhoto;
  final Future<DateTime?> Function()? pickDate;

  @override
  State<WholesaleFormDialog> createState() => _WholesaleFormDialogState();
}

class _WholesaleFormDialogState extends State<WholesaleFormDialog> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.offer?.name ?? '');
  late final price = TextEditingController(text: widget.offer == null ? '' : '${widget.offer!.price}');
  late final minQuantity = TextEditingController(text: widget.offer?.minQuantity ?? '');
  late final wholesaler = TextEditingController(text: widget.offer?.wholesaler ?? '');
  late final phone = TextEditingController(text: widget.offer?.phone ?? '');
  late DateTime? validUntil = widget.offer?.validUntil;
  XFile? photo;
  String? error;

  @override
  void dispose() {
    for (final field in [name, price, minQuantity, wholesaler, phone]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _photo() async {
    try {
      final picked = await (widget.pickPhoto ?? () => ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85))();
      if (picked != null && mounted) setState(() => photo = picked);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _date() async {
    final now = widget.now;
    final picked = await (widget.pickDate ?? () => showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 730)), initialDate: now))();
    if (picked != null && mounted) setState(() => validUntil = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
  }

  void _save() {
    final ok = formKey.currentState!.validate();
    final hasPhoto = photo != null || widget.offer != null;
    setState(() => error = !hasPhoto ? 'Add a photo' : validUntil == null ? 'Choose the validity date' : null);
    if (!ok || error != null) return;
    Navigator.pop(
      context,
      WholesaleDraft({
        if (widget.offer != null) 'offerId': widget.offer!.id,
        if (widget.offer != null) 'photoUrl': widget.offer!.photoUrl,
        'name': name.text.trim(),
        'price': num.parse(price.text.trim()),
        'minQuantity': minQuantity.text.trim(),
        'validUntil': validUntil!.millisecondsSinceEpoch,
        'wholesaler': wholesaler.text.trim(),
        'phone': phone.text.trim(),
      }, photo),
    );
  }

  Widget _field(String key, TextEditingController controller, String label, String problem, {TextInputType? keyboard}) => TextFormField(
    key: ValueKey('wholesale-$key'),
    controller: controller,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label),
    validator: (v) => (v ?? '').trim().isEmpty ? problem : null,
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.offer == null ? 'Add wholesale offer' : 'Edit wholesale offer'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _field('name', name, 'Item name', 'Enter the item name'),
            TextFormField(
              key: const ValueKey('wholesale-price'),
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Wholesale price (₹)'),
              validator: (v) => (num.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter a price above 0' : null,
            ),
            _field('min', minQuantity, 'Minimum quantity (for example 10 kg)', 'Enter the minimum quantity'),
            _field('wholesaler', wholesaler, 'Wholesaler name', 'Enter the wholesaler name'),
            _field('phone', phone, 'Contact number', 'Enter the contact number', keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(key: const ValueKey('wholesale-date'), onPressed: _date, icon: const Icon(Icons.event_outlined), label: Text(validUntil == null ? 'Valid until' : 'Valid until ${premiumDate(validUntil!)}')),
              OutlinedButton.icon(
                key: const ValueKey('wholesale-photo'),
                onPressed: _photo,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(photo != null ? 'Photo chosen' : widget.offer == null ? 'Add photo' : 'Change photo'),
              ),
            ]),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, key: const ValueKey('wholesale-error'), style: const TextStyle(color: Colors.red))),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('wholesale-save'), onPressed: _save, child: const Text('Save')),
    ],
  );
}
