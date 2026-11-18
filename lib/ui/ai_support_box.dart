import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/store.dart';
import '../domain/support_case.dart';
import '../domain/support_limits.dart';
import '../domain/support_texts.dart';
import '../services/app_monitoring.dart';
import '../services/difficulty_watch.dart';
import '../services/photo_compress.dart';
import 'my_support_page.dart';
import 'support_shell.dart';

/// The "AI Support" box (AI Agent + Health System part 3, 17 Nov 2026), opened by itself next to the highlighted option when a person
/// meets a problem in the website, the admin panel or the Vendor, Staff and User apps (lib/ui/support_shell.dart), in their language.
///   * USER side (they can fix it): "Your problem is: …", Step 1, 2, 3 and a one-tap fix (Turn on location, Allow permission, Login
///     again, Try again), then "Did this solve it?" Yes closes; No sends it to the team.
///   * OUR or DEVICE side: no technical words; it is sent to the admin by itself and says "We understood the problem … within 1 day"
///     (the days are the admin's, settings/support.replyDays).
///   * "Tell us more" with an optional screenshot, and a question box (AI answers only when the admin turned it on, within the daily
///     number; otherwise the question goes to the team). The status Sent → Seen → Solved shows here and in "My problem reports".
class AiSupportBox extends StatefulWidget {
  const AiSupportBox({super.key, required this.store, required this.supportCase, required this.close, this.send, this.ask, this.pickScreenshot, this.fix});
  final Store store;
  final SupportCase supportCase;
  final VoidCallback close;

  /// Test seams: the server calls, the screenshot picker and the one-tap fixes.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? send;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? ask;
  final Future<String?> Function()? pickScreenshot;
  final Future<void> Function(SupportFix fix)? fix;

  /// Puts the box into every app (called once from each main()).
  static void install() {
    SupportShell.boxBuilder = (context, store, c, close) => AiSupportBox.positioned(context, store: store, supportCase: c, close: close);
  }

  /// The box at the right side on a wide screen, at the bottom on a phone.
  static Widget positioned(BuildContext context, {required Store store, required SupportCase supportCase, required VoidCallback close}) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    final box = AiSupportBox(store: store, supportCase: supportCase, close: close);
    return wide
        ? Positioned(right: 12, top: 72, bottom: 12, width: 380, child: box)
        : Positioned(left: 0, right: 0, bottom: 0, height: (size.height * 0.72).clamp(320, 640).toDouble(), child: box);
  }

  @override
  State<AiSupportBox> createState() => _AiSupportBoxState();
}

class _AiSupportBoxState extends State<AiSupportBox> {
  final more = TextEditingController();
  final question = TextEditingController();
  String? ticketId;
  String status = '';
  String? screenshot;
  String? aiAnswer;
  String? note;
  bool busy = false;

  SupportCase get c => widget.supportCase;
  String get lang => supportLang(widget.store.language);
  SupportHelp? get help => c.userSide ? supportHelp(c.cause.cause, lang) : null;

  /// Our side, device side, or a user cause with no written help: sent to the team by itself.
  bool get automatic => help == null;

  @override
  void initState() {
    super.initState();
    if (automatic) _send(auto: true);
  }

  @override
  void dispose() {
    more.dispose();
    question.dispose();
    super.dispose();
  }

  Map<String, dynamic> _ticket({required bool auto, String text = ''}) => {
    ...AppMonitoring.reportHeader(),
    'problemKind': c.kind,
    'cause': c.cause.cause,
    'side': c.cause.side,
    'message': c.message,
    'screen': c.screen.isEmpty ? AppMonitoring.screen : c.screen,
    'option': c.option,
    'text': text,
    'lang': widget.store.language,
    'auto': auto,
    'screenshot': ?screenshot,
    'ticketId': ?ticketId,
  };

  Future<void> _send({required bool auto, String text = ''}) async {
    setState(() { busy = true; note = null; });
    try {
      final r = await (widget.send ?? (d) => widget.store.call('openSupportTicket', d))(_ticket(auto: auto, text: text));
      ticketId = '${r['id'] ?? ticketId ?? ''}';
      status = '${r['status'] ?? 'sent'}';
      screenshot = null;
      try {
        (await SharedPreferences.getInstance()).setBool(MySupportPage.hasTicketsKey, true);
      } catch (_) {}
      if (!auto && mounted) setState(() => note = supportWord('thanks', lang));
    } catch (e) {
      if (mounted) setState(() => note = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _ask() async {
    final q = question.text.trim();
    if (q.isEmpty) return;
    setState(() { busy = true; aiAnswer = null; });
    try {
      final r = await (widget.ask ?? (d) => widget.store.call('askSupport', d))({
        'question': q,
        'lang': widget.store.language,
        'deviceId': AppMonitoring.deviceId,
        'context': {'app': AppMonitoring.app, 'screen': c.screen, 'message': c.message, 'cause': c.cause.cause},
      });
      final text = '${r['text'] ?? ''}'.trim();
      if (text.isNotEmpty) {
        if (mounted) setState(() => aiAnswer = text);
      } else {
        // AI is off or today's answers are used: the question goes to the team, who answer in "My problem reports".
        if (mounted) setState(() => aiAnswer = supportWord('aiOff', lang));
        await _send(auto: false, text: q);
      }
      question.clear();
    } catch (e) {
      if (mounted) setState(() => aiAnswer = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pick() async {
    try {
      final picked = await (widget.pickScreenshot ??
          () async {
            final file = await ImagePicker().pickImage(source: ImageSource.gallery);
            if (file == null) return null;
            final small = await shrinkProblemShotInBackground(await file.readAsBytes());
            return small == null ? null : base64Encode(small);
          })();
      if (picked != null && mounted) setState(() => screenshot = picked);
    } catch (_) {}
  }

  Future<void> _fix(SupportFix f) async {
    if (widget.fix != null) return widget.fix!(f);
    switch (f) {
      case SupportFix.locationSettings:
        if (!kIsWeb) await Geolocator.openLocationSettings();
      case SupportFix.appSettings:
        if (!kIsWeb) await Geolocator.openAppSettings();
      case SupportFix.loginAgain:
        widget.close();
        await widget.store.logout();
      case SupportFix.tryAgain:
      case SupportFix.none:
        widget.close();
    }
  }

  void _openMine() {
    final nav = SupportNavigatorObserver.last?.navigator;
    widget.close();
    nav?.push(MaterialPageRoute<void>(builder: (_) => MySupportPage(store: widget.store)));
  }

  Widget _statusRow() {
    const order = ['sent', 'seen', 'solved'];
    final at = order.indexOf(status);
    return Wrap(key: const ValueKey('ai-support-status'), spacing: 2, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('${supportWord('status', lang)}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
      for (var i = 0; i < order.length; i++) ...[
        if (i > 0) Icon(Icons.arrow_forward, size: 14, color: i <= at ? Colors.green : Colors.black26),
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text(supportStatus(order[i], lang), style: TextStyle(fontSize: 12, color: i <= at ? Colors.white : Colors.black54)),
          backgroundColor: i <= at ? Colors.green : const Color(0xFFEEEEEE),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final h = help;
    final days = limitValue(widget.store.entries('settings'), 'replyDays').round();
    final kIsFixable = h != null && h.fix != SupportFix.none && !(kIsWeb && (h.fix == SupportFix.locationSettings || h.fix == SupportFix.appSettings));
    return Material(
      key: const ValueKey('ai-support-box'),
      elevation: 16,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      // Its own Overlay: the box sits above the app's screens, and its text fields need one for the cursor and selection.
      child: Overlay(initialEntries: [
        OverlayEntry(
          builder: (context) => SafeArea(
            top: false,
            child: Column(children: [
              Container(
                color: const Color(0xFF1565C0),
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(children: [
                  const Icon(Icons.support_agent, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text(supportWord('title', lang), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
                  IconButton(key: const ValueKey('ai-support-close'), tooltip: supportWord('close', lang), onPressed: widget.close, icon: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (h != null) ...[
                    Text(supportWord('yourProblem', lang), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(h.problem, key: const ValueKey('ai-support-problem'), style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < h.steps.length; i++)
                      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('${supportWord('step', lang)} ${i + 1}: ${h.steps[i]}', key: ValueKey('ai-support-step-$i'))),
                    if (kIsFixable)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: FilledButton.icon(key: const ValueKey('ai-support-fix'), onPressed: () => _fix(h.fix), icon: const Icon(Icons.build_circle_outlined), label: Text(h.fixLabel)),
                      ),
                    if (status.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(supportWord('solved?', lang), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Wrap(spacing: 8, children: [
                        OutlinedButton(key: const ValueKey('ai-support-yes'), onPressed: widget.close, child: Text(supportWord('yes', lang))),
                        FilledButton.tonal(key: const ValueKey('ai-support-no'), onPressed: busy ? null : () => _send(auto: false, text: more.text.trim()), child: Text(supportWord('no', lang))),
                      ]),
                    ],
                  ] else
                    Text(supportOursMessage(lang, days < 1 ? 1 : days), key: const ValueKey('ai-support-ours'), style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  if (status.isNotEmpty) _statusRow(),
                  if (note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(note!, key: const ValueKey('ai-support-note'))),
                  const Divider(height: 24),
                  TextField(
                    key: const ValueKey('ai-support-more'),
                    controller: more,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: InputDecoration(labelText: supportWord('tellMore', lang), border: const OutlineInputBorder()),
                  ),
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    TextButton.icon(key: const ValueKey('ai-support-shot'), onPressed: busy ? null : _pick, icon: Icon(screenshot == null ? Icons.add_photo_alternate_outlined : Icons.check_circle, color: screenshot == null ? null : Colors.green), label: Text(supportWord('screenshot', lang))),
                    FilledButton(
                      key: const ValueKey('ai-support-send'),
                      onPressed: busy ? null : () {
                        final text = more.text.trim();
                        if (text.isEmpty && screenshot == null) return;
                        more.clear();
                        _send(auto: false, text: text);
                      },
                      child: Text(supportWord('send', lang)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('ai-support-question'),
                        controller: question,
                        decoration: InputDecoration(labelText: supportWord('ask', lang), border: const OutlineInputBorder(), isDense: true),
                        onSubmitted: (_) => _ask(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(key: const ValueKey('ai-support-ask'), tooltip: supportWord('askButton', lang), onPressed: busy ? null : _ask, icon: const Icon(Icons.send)),
                  ]),
                  if (aiAnswer != null)
                    Container(
                      key: const ValueKey('ai-support-answer'),
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(8)),
                      child: SelectableText(aiAnswer!),
                    ),
                  if (busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: null)),
                  const SizedBox(height: 8),
                  TextButton.icon(key: const ValueKey('ai-support-mine'), onPressed: _openMine, icon: const Icon(Icons.history), label: Text(supportWord('myReports', lang))),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
