import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/search_providers.dart';
import 'admin_settings.dart';

/// The box at the top of the admin panel: type or say a setting's name or its number in the Settings list ("5", "5.12", "post
/// duration", "scrolling text") and the matching settings show; a tap opens that setting at once. No AI, no server: the list is in the
/// app and the voice is turned into text on the device.
class AdminSettingsSearchBar extends StatefulWidget {
  const AdminSettingsSearchBar({super.key, required this.store, this.listen, this.open});
  final Store store;

  /// Test seams: the voice input, and what a tap opens (the section page by default).
  final Future<String> Function()? listen;
  final void Function(AdminSettingHit hit)? open;

  @override
  State<AdminSettingsSearchBar> createState() => _AdminSettingsSearchBarState();
}

class _AdminSettingsSearchBarState extends State<AdminSettingsSearchBar> {
  final query = TextEditingController();
  final index = adminSettingsIndex();
  String? note;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void _open(AdminSettingHit hit) {
    if (widget.open != null) return widget.open!(hit);
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => adminSettingsSectionPage(widget.store, hit.sectionKey, focus: hit.isField ? hit.title : null)),
    );
  }

  Future<void> _voice() async {
    setState(() => note = 'Listening…');
    try {
      final text = await (widget.listen ?? DeviceVoiceSearch(localeId: voiceLocaleFor(widget.store.language)).transcribe)();
      if (!mounted) return;
      setState(() {
        query.text = text;
        note = null;
      });
    } catch (e) {
      if (mounted) setState(() => note = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hits = searchAdminSettings(query.text, index: index);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('admin-settings-search'),
            controller: query,
            onChanged: (_) => setState(() => note = null),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.manage_search),
              hintText: 'Find a setting by name or number (e.g. "post duration" or 5.12)',
              border: const OutlineInputBorder(),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (query.text.isNotEmpty)
                  IconButton(key: const ValueKey('admin-settings-search-clear'), tooltip: 'Clear', onPressed: () => setState(query.clear), icon: const Icon(Icons.close)),
                IconButton(key: const ValueKey('admin-settings-search-mic'), tooltip: 'Speak', onPressed: _voice, icon: const Icon(Icons.mic_none)),
              ]),
            ),
          ),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, key: const ValueKey('admin-settings-search-note'))),
          if (query.text.trim().isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Material(
                elevation: 2,
                child: hits.isEmpty
                    ? const ListTile(key: ValueKey('admin-settings-search-none'), title: Text('No setting with that name or number'))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final hit in hits.take(30))
                            ListTile(
                              key: ValueKey('admin-settings-hit-${hit.serial}'),
                              dense: true,
                              leading: CircleAvatar(radius: 16, child: Text(hit.serial, style: const TextStyle(fontSize: 11))),
                              title: Text(hit.label),
                              subtitle: hit.isField ? null : Text(hit.hint, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => _open(hit),
                            ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
