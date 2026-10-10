import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/localization.dart';

/// The language picker shown both on the sign-in form and on the signed-in
/// profile view. Extracted because the two call sites were byte-for-byte
/// identical; `onChanged` is wired exactly as each caller wired it before.
class AccountLanguageField extends StatelessWidget {
  const AccountLanguageField({
    super.key,
    required this.store,
    required this.onChanged,
  });
  final Store store;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: AppLocale.names.containsKey(store.language)
        ? store.language
        : 'en',
    decoration: const InputDecoration(labelText: 'Language / भाषा'),
    items: AppLocale.names.entries
        .where(
          (entry) => AppLocale.enabled(
            store.business.text('enabledLanguages'),
          ).any((locale) => locale.languageCode == entry.key),
        )
        .map(
          (entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        )
        .toList(),
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}
