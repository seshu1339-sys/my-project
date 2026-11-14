import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/search_providers.dart';
import 'admin_groups.dart';
import 'admin_routes.dart';
import 'admin_settings.dart';

/// The box at the top of the admin panel: type or say a setting's name or its number in the Settings list ("5", "5.12", "post
/// duration", "scrolling text") and the matching settings show; a tap opens that setting at once. No AI, no server: the list is in the
/// app and the voice is turned into text on the device.
class AdminSettingsSearchBar extends StatefulWidget {
  const AdminSettingsSearchBar({super.key, required this.store, this.listen, this.open, this.askAi});
  final Store store;

  /// Test seams: the voice input, what a tap opens (the section page by default), and the AI search (askAdminSearch by default).
  final Future<String> Function()? listen;
  final void Function(AdminSettingHit hit)? open;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? askAi;

  @override
  State<AdminSettingsSearchBar> createState() => _AdminSettingsSearchBarState();
}

class _AdminSettingsSearchBarState extends State<AdminSettingsSearchBar> {
  final query = TextEditingController();
  final index = adminSettingsIndex();
  String? note;
  // The AI's answer and the settings it chose, for the words asked ([aiFor]).
  String? aiAnswer, aiFor;
  List<AdminSettingHit> aiHits = const [];
  bool asking = false;

  /// Only when the normal search finds nothing: Claude Haiku 5.5 reads every setting of the panel (with the current values) and
  /// answers which one it is (functions/modules/admin-assistant askAdminSearch). Its daily limit never stops the normal search.
  Future<void> _askAi() async {
    final q = query.text.trim();
    if (q.isEmpty || asking) return;
    setState(() { asking = true; aiAnswer = null; aiHits = const []; aiFor = q; });
    try {
      final data = {
        'query': q,
        'index': [
          for (final h in index) {'serial': h.serial, 'label': [adminGroupOf(h.sectionKey) ?? h.hint, if (h.isField) h.section, h.title].where((x) => x.isNotEmpty).join(' > '), 'key': h.isField ? h.hint : h.sectionKey, 'value': adminSettingValue(widget.store, h)},
        ],
      };
      final result = await (widget.askAi ?? (d) => widget.store.call('askAdminSearch', d))(data);
      final serials = [for (final s in result['serials'] as List? ?? const []) '$s'];
      if (!mounted) return;
      setState(() {
        aiAnswer = '${result['answer'] ?? ''}';
        aiHits = [for (final s in serials) ...index.where((h) => h.serial == s)];
      });
    } catch (e) {
      if (mounted) setState(() => aiAnswer = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').replaceFirst('Bad state: ', ''));
    }
    if (mounted) setState(() => asking = false);
  }

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
      // Owner, 14 Nov 2026: when the words name one page ("Cells", "ప్లాన్స్ తెరువు"), it opens at once.
      final page = bestAdminPage(text, index: index);
      if (page != null) _open(page);
    } catch (e) {
      if (mounted) setState(() => note = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    // "open" / "తెరువు" and the like are left out (lib/ui/admin_routes.dart); Telugu names are found through the route map.
    final hits = searchAdminSettings(adminCommandQuery(query.text), index: index);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('admin-settings-search'),
            controller: query,
            onChanged: (_) => setState(() => note = null),
            // Enter opens the page the words name, else the first match.
            onSubmitted: (text) {
              final page = bestAdminPage(text, index: index) ?? hits.firstOrNull;
              if (page != null) _open(page);
            },
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
                    ? ListView(shrinkWrap: true, children: [
                        const ListTile(key: ValueKey('admin-settings-search-none'), title: Text('No setting with that name or number')),
                        if (aiFor != query.text.trim())
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: OutlinedButton.icon(key: const ValueKey('admin-settings-ask-ai'), onPressed: asking ? null : _askAi, icon: const Icon(Icons.auto_awesome_outlined), label: Text(asking ? 'Asking…' : 'AI ని అడుగు (Ask AI)')),
                          ),
                        if (asking) const LinearProgressIndicator(),
                        if (aiAnswer != null && aiFor == query.text.trim()) ...[
                          ListTile(key: const ValueKey('admin-settings-ai-answer'), leading: const Icon(Icons.auto_awesome_outlined), title: Text(aiAnswer!)),
                          for (final hit in aiHits)
                            ListTile(
                              key: ValueKey('admin-settings-ai-hit-${hit.serial}'),
                              dense: true,
                              leading: CircleAvatar(radius: 16, child: Text(hit.serial, style: const TextStyle(fontSize: 11))),
                              title: Text(hit.label),
                              onTap: () => _open(hit),
                            ),
                        ],
                      ])
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
