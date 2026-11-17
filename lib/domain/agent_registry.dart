// The settings registry of the admin command box (owner spec A-C, 17 Nov 2026): every admin page, setting and design property with
// one unique ID, a deep link, where it is, which platform it belongs to, what it does, and the English + Telugu words people use for it.
// The list itself is made from the panel's own lists (lib/ui/agent_registry_build.dart), so a new option is in it by itself. This file
// holds only the model and the FREE local match: no AI and no server. The AI is asked only when this finds nothing.

/// The platforms of step 1 in the command box: the website (with this admin panel) or one of the three Android apps.
enum AgentPlatform { website, vendor, staff, user }

extension AgentPlatformText on AgentPlatform {
  String get label => switch (this) {
    AgentPlatform.website => 'Website',
    AgentPlatform.vendor => 'Vendor app',
    AgentPlatform.staff => 'Staff app',
    AgentPlatform.user => 'User app',
  };
  String get te => switch (this) {
    AgentPlatform.website => 'వెబ్‌సైట్',
    AgentPlatform.vendor => 'వెండర్ యాప్',
    AgentPlatform.staff => 'స్టాఫ్ యాప్',
    AgentPlatform.user => 'యూజర్ యాప్',
  };
}

/// What kind of option an entry is: a whole page, one field of a form, or one design property (size, colour, text).
enum RegistryKind { page, field, design }

/// One option of the admin panel.
class RegistryEntry {
  const RegistryEntry({
    required this.id,
    required this.name,
    required this.path,
    required this.platforms,
    required this.what,
    required this.open,
    this.field = '',
    this.serial = '',
    this.en = const [],
    this.te = const [],
    this.kind = RegistryKind.page,
    this.min,
    this.max,
    this.risky = false,
  });

  /// Unique and stable: `page.<key>`, `field.<section>.<field>`, `design.web.<part>.<field>`, `design.user.<part>.<field>`.
  final String id;
  final String name;

  /// Where it is in the panel: "Settings > Business Profile > Post duration".
  final String path;
  final Set<AgentPlatform> platforms;

  /// One line: what it does.
  final String what;

  /// The page that holds it (the key adminSettingsContent opens: a Settings section, `tab:<name>`, `layout:<part>`, `androidSizes`).
  final String open;

  /// The field to scroll to and highlight on that page ('' for a whole page).
  final String field;

  /// Its number in the Settings list (5, 5.12, P3, R1), '' when it has none.
  final String serial;
  final List<String> en, te;
  final RegistryKind kind;

  /// The safe range of a number (design sizes); null when it is not a number.
  final double? min, max;

  /// True when the option can suspend, delete, deactivate, approve or reject, or reach All India: the agent asks first.
  final bool risky;

  /// The deep link that opens this option on the admin route.
  String get link => '?open=${Uri.encodeQueryComponent(id)}';

  bool get isNumber => min != null && max != null;
}

/// A ranked match of the local search.
class RegistryMatch {
  const RegistryMatch(this.entry, this.score);
  final RegistryEntry entry;

  /// About 0 to 1.2: 1 = every word found exactly, more when the words are exactly its name.
  final double score;
}

/// Telugu and everyday words mapped to one English word, so "రంగు", "rangu" and "colour" all find "color".
const agentSynonyms = <String, String>{
  'colour': 'color', 'colours': 'color', 'colors': 'color', 'రంగు': 'color', 'రంగులు': 'color', 'rangu': 'color',
  'వెడల్పు': 'width', 'wide': 'width', 'wider': 'width', 'vedalpu': 'width', 'widths': 'width',
  'ఎత్తు': 'height', 'tall': 'height', 'taller': 'height', 'ettu': 'height',
  'సైజు': 'size', 'సైజ్': 'size', 'పరిమాణం': 'size', 'saiju': 'size', 'bigger': 'size', 'smaller': 'size', 'big': 'size',
  'ఫాంట్': 'font', 'అక్షరాలు': 'font', 'letters': 'font', 'text-size': 'font',
  'ఐకాన్': 'icon', 'icons': 'icon', 'బొమ్మ': 'icon',
  'బ్యాక్‌గ్రౌండ్': 'background', 'నేపథ్యం': 'background', 'bg': 'background',
  'కెమెరా': 'camera', 'image-search': 'camera',
  'సెర్చ్': 'search', 'వెతుకు': 'search', 'వెతకడం': 'search', 'searchbox': 'search',
  'యాడ్': 'ad', 'యాడ్స్': 'ads', 'ప్రకటన': 'ad', 'ప్రకటనలు': 'ads', 'advert': 'ad', 'advertisement': 'ad',
  'ఆఫర్': 'offer', 'ఆఫర్లు': 'offers', 'ఆఫర్స్': 'offers',
  'బాక్స్': 'box', 'బాక్సులు': 'boxes', 'బాక్సు': 'box',
  'టెక్స్ట్': 'text', 'పేరు': 'name', 'పేర్లు': 'names',
  'todays': 'today', "today's": 'today', 'ఈరోజు': 'today', 'టుడేస్': 'today', 'టుడే': 'today',
  'కుడి': 'right', 'కుడివైపు': 'right', 'right-side': 'right',
  'స్క్రోలింగ్': 'scrolling', 'కదిలే': 'scrolling', 'moving': 'scrolling', 'marquee': 'scrolling', 'ticker': 'scrolling',
  'బోర్డర్': 'border', 'అంచు': 'border', 'radius': 'radius', 'రౌండ్': 'radius', 'corner': 'radius', 'corners': 'radius',
  'ఖాళీ': 'gap', 'spacing': 'gap', 'space': 'gap',
  'ప్రొడక్ట్': 'product', 'ప్రొడక్ట్స్': 'products', 'ఐటమ్': 'item', 'ఐటమ్స్': 'items',
};

/// Words that only carry the command, not what it is about (English, Telugu, and Telugu in English letters).
const _stopWords = {
  'the', 'a', 'an', 'of', 'to', 'in', 'on', 'for', 'and', 'please', 'open', 'show', 'go', 'goto', 'me', 'my', 'is', 'it', 'this',
  'that', 'what', 'where', 'setting', 'settings', 'page', 'option', 'change', 'set', 'make', 'edit', 'with', 'at', 'by',
  'ఈ', 'ఆ', 'ని', 'కి', 'లో', 'ను', 'తెరువు', 'తెరవు', 'ఓపెన్', 'చూపించు', 'చూపు', 'చూపండి', 'తెరవండి', 'వెళ్ళు', 'పేజీ', 'పేజ్', 'మార్చు',
  'మార్చండి', 'చేయి', 'చేయండి', 'యొక్క', 'కావాలి', 'cheyyi', 'marchu', 'teruvu', 'chupinchu', 'ki', 'lo', 'ni',
};

/// Lower case, no punctuation (Telugu letters kept), one space between words.
String agentNormalize(String text) => text
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r"'s\b"), 's')
    .replaceAll(RegExp(r"[^\p{L}\p{M}\p{N}\s.\-]", unicode: true), ' ')
    .replaceAll(RegExp(r'(?<!\d)\.|\.(?!\d)'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// The words of [text] that say what the command is about, each mapped through [agentSynonyms].
List<String> agentWords(String text, {bool keepStop = false}) => [
  for (final w in agentNormalize(text).split(' '))
    if (w.isNotEmpty && (keepStop || !_stopWords.contains(w))) agentSynonyms[w] ?? w,
];

/// The edit distance of two short words (stops early above [limit]).
int editDistance(String a, String b, {int limit = 3}) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var best = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (cur[j] < best) best = cur[j];
    }
    if (best > limit) return limit + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// How well one asked word fits one word of an entry: exact 1, a start of it .85, a spelling slip .7 / .55, inside it .5.
double wordFit(String asked, String word) {
  if (asked == word) return 1;
  if (asked.length >= 3 && word.startsWith(asked)) return .85;
  if (word.length >= 4 && asked.startsWith(word)) return .75;
  if (asked.length >= 4) {
    final d = editDistance(asked, word, limit: 2);
    if (d == 1) return .7;
    if (d == 2 && asked.length >= 7) return .55;
  }
  if (asked.length >= 4 && word.contains(asked)) return .5;
  return 0;
}

/// The words an entry is found by (name, path, keywords, field and id), mapped through [agentSynonyms].
List<String> entryWords(RegistryEntry e) => {
  ...agentWords(e.name, keepStop: true),
  ...agentWords(e.path, keepStop: true),
  for (final k in [...e.en, ...e.te]) ...agentWords(k, keepStop: true),
  ...agentWords(e.field.replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]}')),
}.toList();

/// The local match: every entry of [entries] (only those of [platform] when one is chosen) ranked by how well its words fit the
/// asked words. A number ("5", "5.12", "number 5") finds that serial. Nothing under [minScore] is returned.
List<RegistryMatch> rankRegistry(String query, List<RegistryEntry> entries, {AgentPlatform? platform, double minScore = .45, Map<String, List<String>>? wordCache}) {
  final pool = [for (final e in entries) if (platform == null || e.platforms.contains(platform)) e];
  final plain = agentNormalize(query).replaceAll(RegExp(r'^(no\.?|number|serial|నంబర్)\s*'), '');
  if (plain.isEmpty) return const [];
  if (RegExp(r'^[pr]?\d+(\.\d+)?$').hasMatch(plain)) {
    return [
      for (final e in pool)
        if (e.serial.toLowerCase() == plain) RegistryMatch(e, 1)
        else if (!plain.contains('.') && e.serial.startsWith('$plain.')) RegistryMatch(e, .9),
    ];
  }
  final asked = agentWords(query);
  if (asked.isEmpty) return const [];
  final out = <RegistryMatch>[];
  for (final e in pool) {
    final words = wordCache?[e.id] ?? entryWords(e);
    var total = 0.0;
    var missed = 0;
    for (final a in asked) {
      var best = 0.0;
      for (final w in words) {
        final f = wordFit(a, w);
        if (f > best) best = f;
        if (best == 1) break;
      }
      if (best == 0) missed++;
      total += best;
    }
    var score = total / asked.length;
    // The asked words are the whole name (or a Telugu / other name): that page first.
    final askedText = asked.join(' ');
    final names = [agentWords(e.name).join(' '), for (final k in [...e.en, ...e.te]) agentWords(k).join(' ')];
    if (names.contains(askedText)) {
      // A page named exactly so wins clearly; a field or design property of the same name only a little (an "Offers" field must not
      // hide the "Today's Offers" pages: then the list shows).
      score += e.kind == RegistryKind.page ? .2 : .05;
    } else if (missed == 0 && agentWords(e.name).every(asked.contains)) {
      score += .1;
    }
    // A page before its fields, a field before a design property, when they fit the same.
    score -= switch (e.kind) { RegistryKind.page => 0, RegistryKind.field => .01, RegistryKind.design => .02 };
    if (score >= minScore) out.add(RegistryMatch(e, score));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// The one option the words clearly name (open it at once), or null when the best match is not clear enough (show the top 3).
RegistryEntry? confidentMatch(List<RegistryMatch> ranked) {
  if (ranked.isEmpty) return null;
  final top = ranked.first;
  if (top.score < .85) return null;
  if (ranked.length > 1 && top.score - ranked[1].score < .1) return null;
  return top.entry;
}
