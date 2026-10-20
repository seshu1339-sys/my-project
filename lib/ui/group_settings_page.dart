import 'package:flutter/material.dart';

import '../data/store.dart';
import 'layout_editor.dart';

/// Behavior settings for one home-page section (scroll speed, direction,
/// pause-on-touch, rotation timing) -- deliberately a SEPARATE page from
/// that section's numbered Design panel, per the admin's own 3-way split:
/// changing design must never touch settings, and vice versa. Reuses
/// LayoutFieldsForm's save-to-settings/section_`<component>` plumbing with
/// a fixed, smaller field list (fieldsOverride) instead of the usual
/// design fields, so there's one save/validate implementation, not two.
class GroupSettingsPage extends StatefulWidget {
  const GroupSettingsPage({
    super.key,
    required this.store,
    required this.component,
    required this.title,
    required this.fields,
  });
  final Store store;
  final String component;
  final String title;
  final List<String> fields;
  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  final formKey = GlobalKey<LayoutFieldsFormState>();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => formKey.currentState?.save(),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save settings'),
            ),
            OutlinedButton(
              onPressed: () => formKey.currentState?.save(reset: true),
              child: const Text('Reset these settings to default'),
            ),
          ],
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Behavior only -- color, font and size for this section live in its own numbered Design panel instead.',
        ),
        const SizedBox(height: 16),
        LayoutFieldsForm(
          key: formKey,
          store: widget.store,
          component: widget.component,
          fieldsOverride: widget.fields,
        ),
      ],
    ),
  );
}
