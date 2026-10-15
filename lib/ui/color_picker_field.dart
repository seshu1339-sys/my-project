import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'shared.dart';

/// A labeled color swatch that opens a small picker dialog on tap — presets
/// plus a #RRGGBB hex field for precise entry — instead of asking the admin
/// to type a hex code directly. Stores/returns the same #RRGGBB string
/// format every color field already used (colorFromHex in shared.dart),
/// so no data-model change is needed, only how it's edited.
const _presetColors = <String>[
  '#16A34A', '#0F7A37', '#FF8A3D', '#2F80ED', '#8E5CF6', '#E0A400',
  '#E4483C', '#16241C', '#5B6B61', '#FFF8F0', '#FFFFFF', '#000000',
  '#E6EAE3', '#F43F5E', '#EAB308', '#06B6D4', '#6366F1', '#64748B',
];

class ColorPickerField extends StatelessWidget {
  const ColorPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String value; // '' means unset/default
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = value.trim().isEmpty ? null : colorFromHex(value, Colors.transparent);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final result = await showDialog<String>(
          context: context,
          builder: (_) => _ColorPickerDialog(initial: value),
        );
        if (result != null) onChanged(result);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color ?? Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: AppTokens.border, width: 1.5),
              ),
              child: color == null ? const Icon(Icons.block, size: 14, color: AppTokens.textMuted) : null,
            ),
            const SizedBox(width: 10),
            Text(value.trim().isEmpty ? 'Default' : value.toUpperCase()),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});
  final String initial;
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late final TextEditingController hex = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = hex.text.trim().isEmpty ? null : colorFromHex(hex.text, Colors.transparent);
    return AlertDialog(
      title: const Text('Choose a color'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presetColors)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => hex.text = preset),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colorFromHex(preset, Colors.transparent),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hex.text.toUpperCase() == preset ? AppTokens.textPrimary : AppTokens.border,
                          width: hex.text.toUpperCase() == preset ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: preview ?? Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTokens.border),
                  ),
                  child: preview == null ? const Icon(Icons.block, size: 14, color: AppTokens.textMuted) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: hex,
                    decoration: const InputDecoration(labelText: '#RRGGBB', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Use default'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, hex.text.trim()),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
