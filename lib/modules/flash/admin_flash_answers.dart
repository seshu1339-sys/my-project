import 'package:flutter/material.dart';

import 'flash_answers.dart';

/// Admin > Flash > Ready answers (owner, 18 Nov 2026: cost cuts part 4): the ready-question buttons of every Support Team chat and their
/// stored answers, in English and Telugu, with the keywords that give the same answer to a typed question (no AI). Add, change,
/// switch off or remove any time; [onSave] sends the whole list to saveFlashAnswers, which checks it.
class AdminFlashAnswers extends StatefulWidget {
  const AdminFlashAnswers({super.key, required this.answers, required this.starting, required this.onSave});
  final List<FlashAnswer> answers;

  /// The starting list ("Back to the starting answers").
  final Future<List<FlashAnswer>> Function() starting;
  final Future<Object?> Function(Map<String, dynamic> data) onSave;
  @override
  State<AdminFlashAnswers> createState() => _AdminFlashAnswersState();
}

const _chatNames = {'user': 'Customers', 'vendor': 'Vendors', 'premium': 'Premium vendors', 'provider': 'Service providers', 'staff': 'Staff'};

class _Edit {
  _Edit(FlashAnswer a)
    : id = a.id,
      chats = {...a.chats},
      active = a.active,
      qEn = TextEditingController(text: a.questionEn),
      qTe = TextEditingController(text: a.questionTe),
      aEn = TextEditingController(text: a.answerEn),
      aTe = TextEditingController(text: a.answerTe),
      keywords = TextEditingController(text: a.keywords.join(', '));
  final String id;
  final Set<String> chats;
  bool active;
  final TextEditingController qEn, qTe, aEn, aTe, keywords;

  FlashAnswer toAnswer(int order) => FlashAnswer(
    id: id,
    chats: [for (final c in _chatNames.keys) if (chats.contains(c)) c],
    order: order,
    active: active,
    questionEn: qEn.text.trim(),
    questionTe: qTe.text.trim(),
    answerEn: aEn.text.trim(),
    answerTe: aTe.text.trim(),
    keywords: [for (final k in keywords.text.split(',')) if (k.trim().isNotEmpty) k.trim()],
  );

  void dispose() {
    for (final c in [qEn, qTe, aEn, aTe, keywords]) {
      c.dispose();
    }
  }
}

class _AdminFlashAnswersState extends State<AdminFlashAnswers> {
  late List<_Edit> rows = [for (final a in widget.answers) _Edit(a)];
  bool busy = false;
  String? note;

  @override
  void dispose() {
    for (final r in rows) {
      r.dispose();
    }
    super.dispose();
  }

  String _newId() {
    var n = rows.length + 1;
    while (rows.any((r) => r.id == 'answer_$n')) {
      n++;
    }
    return 'answer_$n';
  }

  Future<void> _save() async {
    setState(() { busy = true; note = null; });
    try {
      await widget.onSave({'items': [for (final (i, r) in rows.indexed) r.toAnswer(i + 1).toMap()]});
      if (mounted) setState(() => note = 'Saved. The chats use it within 5 minutes.');
    } catch (e) {
      if (mounted) setState(() => note = '$e'.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), ''));
    }
    if (mounted) setState(() => busy = false);
  }

  void _move(int i, int by) {
    final j = i + by;
    if (j < 0 || j >= rows.length) return;
    setState(() => rows.insert(j, rows.removeAt(i)));
  }

  Widget _field(String key, TextEditingController c, String label, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(key: ValueKey(key), controller: c, minLines: 1, maxLines: lines, decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder())),
  );

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('admin-flash-answers'),
    padding: const EdgeInsets.all(16),
    children: [
      Text('Ready answers', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'The buttons people see first in the Support Team chat. A tap shows the answer at once, with no AI. A typed question with these '
        'keywords (English, Telugu, Telugu in English letters, separated by commas) gets the same answer, also with no AI. Only when '
        'nothing matches does AI answer, within the daily limit; after that: "Our team will answer you."',
      ),
      const SizedBox(height: 12),
      for (final (i, r) in rows.indexed)
        Card(
          key: ValueKey('flash-answer-${r.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.qEn.text.isEmpty ? 'New answer' : r.qEn.text, style: const TextStyle(fontWeight: FontWeight.w600))),
                Switch(key: ValueKey('flash-answer-on-${r.id}'), value: r.active, onChanged: (v) => setState(() => r.active = v)),
                IconButton(tooltip: 'Up', icon: const Icon(Icons.arrow_upward), onPressed: () => _move(i, -1)),
                IconButton(tooltip: 'Down', icon: const Icon(Icons.arrow_downward), onPressed: () => _move(i, 1)),
                IconButton(
                  key: ValueKey('flash-answer-remove-${r.id}'),
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => rows.removeAt(i).dispose()),
                ),
              ]),
              Wrap(spacing: 6, children: [
                for (final e in _chatNames.entries)
                  FilterChip(
                    key: ValueKey('flash-answer-chat-${r.id}-${e.key}'),
                    label: Text(e.value),
                    selected: r.chats.contains(e.key),
                    onSelected: (on) => setState(() => on ? r.chats.add(e.key) : r.chats.remove(e.key)),
                  ),
              ]),
              _field('flash-answer-q-en-${r.id}', r.qEn, 'Button / question (English)'),
              _field('flash-answer-q-te-${r.id}', r.qTe, 'Button / question (Telugu)'),
              _field('flash-answer-a-en-${r.id}', r.aEn, 'Answer (English)', lines: 5),
              _field('flash-answer-a-te-${r.id}', r.aTe, 'Answer (Telugu)', lines: 5),
              _field('flash-answer-k-${r.id}', r.keywords, 'Keywords (comma separated)', lines: 3),
            ]),
          ),
        ),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          key: const ValueKey('flash-answer-add'),
          onPressed: () => setState(() => rows.add(_Edit(FlashAnswer(id: _newId(), chats: const ['user'], questionEn: '', answerEn: '')))),
          icon: const Icon(Icons.add),
          label: const Text('Add a ready answer'),
        ),
        TextButton(
          onPressed: () async {
            final start = await widget.starting();
            if (!mounted) return;
            setState(() {
              for (final r in rows) {
                r.dispose();
              }
              rows = [for (final a in start) _Edit(a)];
            });
          },
          child: const Text('Back to the starting answers'),
        ),
        FilledButton(key: const ValueKey('flash-answer-save'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
        if (note != null) Text(note!, key: const ValueKey('flash-answer-note')),
      ]),
    ],
  );
}
