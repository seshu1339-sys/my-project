import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../data/store.dart';
import '../../services/strings.dart';

/// The starting ready answers: the same file the server uses (functions/modules/flash/default-answers.json, an asset in pubspec.yaml).
const flashDefaultAnswersAsset = 'functions/modules/flash/default-answers.json';

/// One ready question of the Support Team chat and its stored answer (owner, 18 Nov 2026: cost cuts part 4). A tap shows the answer at
/// once, with no AI; a typed question with its [keywords] gets it from the server, also with no AI.
class FlashAnswer {
  const FlashAnswer({
    required this.id,
    required this.chats,
    this.order = 0,
    this.active = true,
    required this.questionEn,
    this.questionTe = '',
    required this.answerEn,
    this.answerTe = '',
    this.keywords = const [],
  });

  factory FlashAnswer.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic> two(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
    final q = two(m['question']), a = two(m['answer']);
    return FlashAnswer(
      id: '${m['id'] ?? ''}',
      chats: [for (final c in (m['chats'] is List ? m['chats'] as List : const [])) '$c'],
      order: (m['order'] as num?)?.toInt() ?? 0,
      active: m['active'] != false,
      questionEn: '${q['en'] ?? ''}',
      questionTe: '${q['te'] ?? ''}',
      answerEn: '${a['en'] ?? ''}',
      answerTe: '${a['te'] ?? ''}',
      keywords: [for (final k in (m['keywords'] is List ? m['keywords'] as List : const [])) '$k'],
    );
  }

  final String id, questionEn, questionTe, answerEn, answerTe;
  final List<String> chats, keywords;
  final int order;
  final bool active;

  Map<String, dynamic> toMap() => {
    'id': id,
    'chats': chats,
    'order': order,
    'active': active,
    'question': {'en': questionEn, 'te': questionTe},
    'answer': {'en': answerEn, 'te': answerTe},
    'keywords': keywords,
  };

  String question(String language) => language == 'te' && questionTe.isNotEmpty ? questionTe : questionEn;
  String answer(String language) => language == 'te' && answerTe.isNotEmpty ? answerTe : answerEn;
}

List<FlashAnswer> flashAnswersFrom(Object? items) => [
  for (final m in (items is List ? items : const [])) if (m is Map) FlashAnswer.fromMap(Map<String, dynamic>.from(m)),
];

/// The buttons of one chat [kind]: switched on, in the admin's order.
List<FlashAnswer> readyFor(String kind, List<FlashAnswer> all) =>
    [for (final a in all) if (a.active && a.chats.contains(kind) && a.questionEn.isNotEmpty) a]..sort((a, b) => a.order.compareTo(b.order));

/// The starting answers bundled in the app.
Future<List<FlashAnswer>> defaultFlashAnswers() async {
  try {
    return flashAnswersFrom(jsonDecode(await rootBundle.loadString(flashDefaultAnswersAsset))['answers']);
  } catch (_) {
    return const [];
  }
}

/// The admin's ready answers (flashAnswers/main, one read), else the starting ones.
Future<List<FlashAnswer>> loadFlashAnswers(Store store) async {
  if (store.live) {
    try {
      final items = (await store.firestore.collection('flashAnswers').doc('main').get()).data()?['items'];
      if (items is List) return flashAnswersFrom(items);
    } catch (_) {
      /* the starting answers below */
    }
  }
  return defaultFlashAnswers();
}

/// The ready-question buttons at the top of a chat: a tap shows the stored answer at once (no AI, no waiting). [onTap] counts it.
class FlashReadyAnswers extends StatefulWidget {
  const FlashReadyAnswers({super.key, required this.answers, required this.language, this.onTap});
  final List<FlashAnswer> answers;
  final String language;
  final void Function(FlashAnswer answer)? onTap;
  @override
  State<FlashReadyAnswers> createState() => _FlashReadyAnswersState();
}

class _FlashReadyAnswersState extends State<FlashReadyAnswers> {
  FlashAnswer? shown;

  @override
  Widget build(BuildContext context) {
    if (widget.answers.isEmpty) return const SizedBox.shrink();
    final lang = widget.language;
    return Column(
      key: const ValueKey('flash-ready'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick answers'.tr(context), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in widget.answers)
            ChoiceChip(
              key: ValueKey('flash-ready-${a.id}'),
              label: Text(a.question(lang)),
              selected: shown?.id == a.id,
              onSelected: (_) {
                setState(() => shown = a);
                widget.onTap?.call(a);
              },
            ),
        ]),
        if (shown != null)
          Card(
            key: ValueKey('flash-ready-answer-${shown!.id}'),
            margin: const EdgeInsets.only(top: 12),
            color: const Color(0xFFF1F8E9),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shown!.question(lang), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SelectableText(shown!.answer(lang)),
                const SizedBox(height: 8),
                Text('Not solved? Choose a topic below and ask us.'.tr(context), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}
