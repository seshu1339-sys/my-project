import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../domain/agent_command.dart';
import '../domain/agent_registry.dart';
import '../domain/towns.dart';
import '../services/agent_counts.dart';
import '../services/agent_log.dart';
import '../services/search_providers.dart';
import 'admin_ai_assistant.dart';
import 'admin_groups.dart';
import 'admin_settings.dart';
import 'agent_intents.dart';
import 'agent_open.dart';
import 'agent_registry_build.dart';
import 'ai_agent_page.dart';

/// The ONE command box at the top of the admin panel (owner spec A, 17 Nov 2026). It took the place of the "Find a setting" bar and the
/// "AI Agent" button; both still work from here (the AI assistant and the older AI Agent are in its menu).
///   Step 1  the platform: Website, or Android > Vendor / Staff / User app. Then only that platform's options are found.
///   Step 2  typed or said (Telugu / English / mixed): the option opens at its exact field, scrolled to and highlighted. When the words
///           are not clear, the 3 best matches show. A number question is answered from the live data, "what is not working?" lists
///           the failures, and ad / design commands open their own flow (lib/ui/agent_intents.dart).
/// Cost (owner spec C): the free local match runs first (lib/domain/agent_registry.dart); the AI is asked only when it finds nothing,
/// and only when the admin presses "Ask AI".
class AdminSettingsSearchBar extends StatefulWidget {
  const AdminSettingsSearchBar({super.key, required this.store, this.listen, this.open, this.askAi, this.count, this.intents});
  final Store store;

  /// Test seams: the voice input, what opening does (the option's page by default), the AI search (askAdminSearch), the live count,
  /// and the health / ad / design flows.
  final Future<String> Function()? listen;
  final void Function(RegistryEntry entry)? open;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? askAi;
  final Future<String> Function(AgentCommand command)? count;
  final AgentIntentHandlers? intents;

  @override
  State<AdminSettingsSearchBar> createState() => _AdminSettingsSearchBarState();
}

class _AdminSettingsSearchBarState extends State<AdminSettingsSearchBar> {
  final query = TextEditingController();
  late final List<RegistryEntry> registry = buildAgentRegistry();
  late final Map<String, List<String>> _words = {for (final e in registry) e.id: entryWords(e)};
  final index = adminSettingsIndex();
  AgentPlatform? platform;
  String? note;
  bool showAll = false;
  // The AI's answer and the options it chose, for the words asked ([aiFor]).
  String? aiAnswer, aiFor;
  List<RegistryEntry> aiHits = const [];
  bool asking = false;
  // The answer of a count / health command, for the words asked ([answerFor]).
  String? answer, answerFor;
  bool answering = false;

  List<String> get _places => [
    for (final t in parseServiceTowns(widget.store.entries('settings').where((e) => e.id == 'business').firstOrNull?.text('serviceTowns') ?? '')) t.name,
    for (final s in widget.store.entries('shops')) if (s.text('town').isNotEmpty) s.text('town'),
  ];

  AgentCommand _command(String text) => parseAgentCommand(text, places: _places);

  List<RegistryMatch> _rank(String text) => rankRegistry(text, registry, platform: platform, wordCache: _words);

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> _open(RegistryEntry e) async {
    final text = query.text.trim();
    if (widget.open != null) {
      AgentLog.write(widget.store, action: 'open', command: text, target: e.id, platform: platform?.name ?? '');
      return widget.open!(e);
    }
    if (e.risky && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('This page has Approve / Reject / Suspend / Delete buttons: each one asks you to confirm first.')));
    }
    await openAgentEntry(context, widget.store, e, command: text, platform: platform?.name ?? '');
  }

  /// Only when the local match finds nothing: Claude Haiku 5.5 reads the panel's pages and fields with their values and answers which
  /// one it is (functions/modules/admin-assistant askAdminSearch). Its daily limit never stops the local match.
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
      AgentLog.write(widget.store, action: 'ask_ai_search', command: q, target: serials.join(','));
      if (!mounted) return;
      setState(() {
        aiAnswer = '${result['answer'] ?? ''}';
        aiHits = [for (final s in serials) ...registry.where((e) => e.serial == s && e.kind != RegistryKind.design)];
      });
    } catch (e) {
      if (mounted) setState(() => aiAnswer = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').replaceFirst('Bad state: ', ''));
    }
    if (mounted) setState(() => asking = false);
  }

  /// Enter, Go or the end of speaking: do what the words say.
  Future<void> _run(String text, {bool spoken = false}) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final c = _command(q);
    switch (c.intent) {
      case AgentIntent.count:
        return _answer(q, () => (widget.count ?? (c) => answerCount(widget.store, c))(c));
      case AgentIntent.health:
        final handlers = widget.intents ?? defaultAgentIntents;
        return _answer(q, () => handlers.health(context, widget.store));
      case AgentIntent.ad:
      case AgentIntent.rate:
        AgentLog.write(widget.store, action: c.intent.name, command: q, platform: platform?.name ?? '');
        return (widget.intents ?? defaultAgentIntents).ad(context, widget.store, c);
      case AgentIntent.design:
        final ranked = [for (final m in _rank(q)) if (m.entry.kind == RegistryKind.design) m];
        AgentLog.write(widget.store, action: 'design', command: q, platform: platform?.name ?? '');
        return (widget.intents ?? defaultAgentIntents).design(context, widget.store, c, [for (final m in ranked.take(3)) m.entry], platform);
      case AgentIntent.open:
        final ranked = _rank(q);
        final sure = confidentMatch(ranked);
        if (sure != null) return _open(sure);
        // Typed + Enter with no clear winner: the first of the list (as before); spoken: only the list, nothing opens by itself.
        if (!spoken && ranked.isNotEmpty && ranked.first.score >= .85) return _open(ranked.first.entry);
        setState(() => showAll = false);
    }
  }

  Future<void> _answer(String q, Future<String> Function() get) async {
    setState(() { answering = true; answer = null; answerFor = q; });
    try {
      final text = await get();
      AgentLog.write(widget.store, action: 'answer', command: q, details: {'answer': text});
      if (mounted) setState(() => answer = text);
    } catch (e) {
      if (mounted) setState(() => answer = 'Could not get that now: ${'$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')}');
    }
    if (mounted) setState(() => answering = false);
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
      await _run(text, spoken: true);
    } catch (e) {
      if (mounted) setState(() => note = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  void _menu(String choice) {
    final store = widget.store;
    final page = switch (choice) {
      'assistant' => Scaffold(appBar: AppBar(title: const Text('AI assistant')), body: AdminAiAssistantPage(store: store)),
      'older' => AiAgentPage(store: store),
      'log' => adminSettingsSectionPage(store, 'agentLog'),
      'ai' => adminSettingsSectionPage(store, 'aiProvider'),
      _ => (widget.intents ?? defaultAgentIntents).healthPage(store),
    };
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  /// Step 1, at the start of the box (one line, so the panel keeps its room): All, Website, or Android > Vendor / Staff / User app.
  Widget _platforms() => PopupMenuButton<String>(
    key: const ValueKey('agent-platform'),
    tooltip: '1. Choose the platform',
    onSelected: (v) => setState(() => platform = v == 'all' ? null : AgentPlatform.values.byName(v)),
    itemBuilder: (_) => [
      const PopupMenuItem(key: ValueKey('agent-platform-all'), value: 'all', child: Text('All platforms')),
      const PopupMenuItem(key: ValueKey('agent-platform-website'), value: 'website', child: Text('Website (and admin)')),
      const PopupMenuDivider(),
      for (final p in const [AgentPlatform.vendor, AgentPlatform.staff, AgentPlatform.user])
        PopupMenuItem(key: ValueKey('agent-platform-${p.name}'), value: p.name, child: Text('Android › ${p.label}')),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(platform == null || platform == AgentPlatform.website ? Icons.language : Icons.phone_android, size: 18),
        const SizedBox(width: 4),
        Text(platform?.label ?? 'All', key: const ValueKey('agent-platform-label'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const Icon(Icons.arrow_drop_down, size: 18),
      ]),
    ),
  );

  Widget _hitTile(RegistryEntry e, {String keyPrefix = 'admin-settings-hit'}) => ListTile(
    key: ValueKey('$keyPrefix-${e.serial.isNotEmpty && e.kind != RegistryKind.design ? e.serial : e.id}'),
    dense: true,
    leading: CircleAvatar(radius: 16, child: Text(e.serial.isEmpty ? (e.kind == RegistryKind.design ? 'D' : '•') : e.serial, style: const TextStyle(fontSize: 11))),
    title: Text(e.kind == RegistryKind.page ? e.name : e.path.replaceFirst('Settings > ', ''), maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text('${e.platforms.map((p) => p.label).join(' · ')}  —  ${e.what}', maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
      if (e.risky) const Tooltip(message: 'Has risky buttons: they ask to confirm', child: Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange)),
      IconButton(
        tooltip: 'Copy link',
        icon: const Icon(Icons.link, size: 18),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: Uri.base.replace(queryParameters: {'open': e.id}).toString()));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Link copied: ${e.link}')));
        },
      ),
    ]),
    onTap: () => _open(e),
  );

  @override
  Widget build(BuildContext context) {
    final text = query.text.trim();
    final c = text.isEmpty ? null : _command(text);
    final ranked = c == null || c.intent == AgentIntent.count || c.intent == AgentIntent.health ? const <RegistryMatch>[] : _rank(text);
    final shown = showAll ? ranked.take(30) : ranked.take(3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('admin-settings-search'),
            controller: query,
            onChanged: (_) => setState(() { note = null; showAll = false; }),
            onSubmitted: (t) => _run(t),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: _platforms(),
              hintText: platform == null
                  ? 'Type or say: "post duration", "5.12", "ఈరోజు ఎన్ని వెండర్లు", "what is not working?"'
                  : '${platform!.label}: type or say an option, a question or a command',
              border: const OutlineInputBorder(),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (query.text.isNotEmpty)
                  IconButton(key: const ValueKey('admin-settings-search-clear'), tooltip: 'Clear', onPressed: () => setState(query.clear), icon: const Icon(Icons.close)),
                IconButton(key: const ValueKey('admin-settings-search-mic'), tooltip: 'Speak (Telugu / English)', onPressed: _voice, icon: const Icon(Icons.mic_none)),
                IconButton(key: const ValueKey('agent-go'), tooltip: 'Go', onPressed: () => _run(query.text), icon: const Icon(Icons.arrow_forward)),
                PopupMenuButton<String>(
                  key: const ValueKey('agent-menu'),
                  tooltip: 'Agent menu: AI assistant, older AI Agent, Health, log, AI key',
                  onSelected: _menu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'assistant', child: ListTile(leading: Icon(Icons.smart_toy_outlined), title: Text('AI assistant (questions)'))),
                    PopupMenuItem(value: 'older', child: ListTile(leading: Icon(Icons.history), title: Text('Older AI Agent'))),
                    PopupMenuItem(value: 'health', child: ListTile(leading: Icon(Icons.monitor_heart_outlined), title: Text('Health'))),
                    PopupMenuItem(value: 'log', child: ListTile(leading: Icon(Icons.receipt_long_outlined), title: Text('Agent log'))),
                    PopupMenuItem(value: 'ai', child: ListTile(leading: Icon(Icons.key_outlined), title: Text('AI provider & usage'))),
                  ],
                ),
              ]),
            ),
          ),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, key: const ValueKey('admin-settings-search-note'))),
          if (text.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Material(
                elevation: 2,
                child: ListView(shrinkWrap: true, children: [
                  if (c!.intent != AgentIntent.open)
                    ListTile(
                      key: const ValueKey('agent-intent'),
                      dense: true,
                      leading: Icon(switch (c.intent) {
                        AgentIntent.count => Icons.numbers,
                        AgentIntent.health => Icons.monitor_heart_outlined,
                        AgentIntent.ad || AgentIntent.rate => Icons.campaign_outlined,
                        _ => Icons.palette_outlined,
                      }),
                      title: Text(switch (c.intent) {
                        AgentIntent.count => 'Live number — press Enter (no AI)',
                        AgentIntent.health => 'What is not working — press Enter',
                        AgentIntent.ad => 'Ad by command — press Enter to open the ad form',
                        AgentIntent.rate => 'Live rate — press Enter to open the ad form',
                        _ => 'Design change — press Enter, then choose the value',
                      }),
                    ),
                  if (answering) const LinearProgressIndicator(),
                  if (answer != null && answerFor == text)
                    ListTile(key: const ValueKey('agent-answer'), leading: const Icon(Icons.info_outline), title: SelectableText(answer!)),
                  if (ranked.isEmpty && (c.intent == AgentIntent.open || c.intent == AgentIntent.design)) ...[
                    const ListTile(key: ValueKey('admin-settings-search-none'), title: Text('No setting with that name or number')),
                    if (aiFor != text)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: OutlinedButton.icon(key: const ValueKey('admin-settings-ask-ai'), onPressed: asking ? null : _askAi, icon: const Icon(Icons.auto_awesome_outlined), label: Text(asking ? 'Asking…' : 'AI ని అడుగు (Ask AI)')),
                      ),
                    if (asking) const LinearProgressIndicator(),
                    if (aiAnswer != null && aiFor == text) ...[
                      ListTile(key: const ValueKey('admin-settings-ai-answer'), leading: const Icon(Icons.auto_awesome_outlined), title: Text(aiAnswer!)),
                      for (final e in aiHits) _hitTile(e, keyPrefix: 'admin-settings-ai-hit'),
                    ],
                  ],
                  for (final m in shown) _hitTile(m.entry),
                  if (!showAll && ranked.length > 3)
                    TextButton(key: const ValueKey('agent-show-all'), onPressed: () => setState(() => showAll = true), child: Text('Show all ${ranked.length > 30 ? '30+' : ranked.length} matches')),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
