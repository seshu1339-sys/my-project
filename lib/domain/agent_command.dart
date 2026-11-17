// What the admin asked in the command box (typed or said, Telugu / English / mixed), read with plain rules (no AI):
//   open    "post duration", "ప్లాన్స్ తెరువు"                        -> find the option and open it
//   count   "how many vendors added today in Narsipatnam", "ఈరోజు ఎన్ని వెండర్లు"  -> a number from the live data
//   health  "what is not working?", "ఏం పని చేయట్లేదు"                   -> the list of failures
//   ad      "this photo, Today's Offers, Narsipatnam, 10 km, 2 days"     -> the ad form, filled in
//   rate    "show this live rate / price"                                -> the live-rate ad form
//   design  "make the search box wider", "Today's Offers రంగు మార్చు"       -> the design field, then its value
import 'agent_registry.dart';

enum AgentIntent { open, count, health, ad, rate, design }

/// Where an admin ad shows (owner, 17 Nov 2026: town / district / state / All India are for ADMIN ads only; vendors stay km-only).
enum AdReach { radius, town, district, state, allIndia }

/// The live numbers the box can answer without AI.
enum AgentMetric { vendorsAdded, vendorsWaiting, vendorsApproved, itemsAdded, pricesChanged, staffAdded, searches, shops, products }

/// The days a count covers.
enum AgentPeriod { today, yesterday, week, month }

class AgentCommand {
  const AgentCommand(this.intent, this.text, {this.metric, this.period = AgentPeriod.today, this.place = '', this.km, this.days, this.hours, this.reach, this.placement = '', this.value = ''});
  final AgentIntent intent;

  /// What was asked, as typed.
  final String text;
  final AgentMetric? metric;
  final AgentPeriod period;

  /// A town / district / state named in it ('' when none).
  final String place;
  final double? km;
  final int? days, hours;
  final AdReach? reach;

  /// 'todaysOffers' or 'rightBox' for an ad ('' when not said).
  final String placement;

  /// A value said with a design change ("red", "#ff0000", "20", "+10", "10%").
  final String value;
}

bool _any(String text, List<String> words) => words.any(text.contains);

const _healthWords = [
  'not working', 'what is broken', "what's broken", 'whats broken', 'errors', 'failing', 'failures', 'problems', 'health', 'is down',
  'పని చేయట్లేదు', 'పనిచేయట్లేదు', 'పని చేయడం లేదు', 'పనిచేయడం లేదు', 'పని చెయ్యట్లేదు', 'సమస్యలు', 'లోపాలు', 'ఎర్రర్', 'పాడైంది', 'pani cheyatledu',
];
const _countWords = ['how many', 'how much', 'count', 'number of', 'total', 'ఎన్ని', 'ఎంత మంది', 'ఎందరు', 'ఎంతమంది', 'enni', 'entha mandi'];
const _adWords = ["today's offers", 'todays offers', 'today offers', "today's offer", 'todays offer', 'right side ad', 'right ad', 'ad box', 'right box',
  'టుడేస్ ఆఫర్', 'ఈరోజు ఆఫర్', 'యాడ్', 'ప్రకటన', 'advert', ' ad ', 'ad,', ' ads '];
// Besides a km, a number of days or hours (read by kmOf / daysOf / hoursOf, never "day" inside "today").
const _adDetailWords = ['all india', 'india', 'ఇండియా', 'భారత', 'district', 'జిల్లా', 'state', 'రాష్ట్ర', 'this photo', 'ఈ ఫోటో', 'photo', 'ఫోటో', ' town', 'ఊరు', 'పట్టణం'];
const _rateWords = ['live rate', 'live price', "today's rate", 'todays rate', 'rate', 'ధర', 'రేటు', 'రేట్'];
const _designWords = [
  'color', 'colour', 'రంగు', 'rangu', 'wider', 'narrower', 'width', 'వెడల్పు', 'bigger', 'smaller', 'larger', 'size', 'సైజు', 'సైజ్', 'height',
  'taller', 'shorter', 'ఎత్తు', 'font', 'ఫాంట్', 'icon size', 'background', 'బ్యాక్‌గ్రౌండ్', 'border', 'radius', 'padding', 'margin', 'gap',
  'పెద్దగా', 'పెద్దది', 'చిన్నగా', 'చిన్నది', 'rename', 'text to', 'పేరు మార్చు', 'టెక్స్ట్ మార్చు',
];

/// The live number asked for, from its words ("vendors added", "ఐటమ్స్", "waiting").
AgentMetric? metricOf(String t) {
  bool has(List<String> w) => _any(t, w);
  final vendor = has(['vendor', 'వెండర్', 'shop owner', 'దుకాణదారు']);
  if (vendor && has(['waiting', 'pending', 'approval', 'ఆమోదం', 'వెయిటింగ్', 'పెండింగ్'])) return AgentMetric.vendorsWaiting;
  if (vendor && has(['approved', 'active', 'live', 'ఆమోదించిన', 'యాక్టివ్'])) return AgentMetric.vendorsApproved;
  if (vendor) return AgentMetric.vendorsAdded;
  if (has(['staff', 'స్టాఫ్', 'field assistant'])) return AgentMetric.staffAdded;
  if (has(['price', 'rate', 'ధర', 'రేటు', 'రేట్'])) return AgentMetric.pricesChanged;
  if (has(['item', 'ఐటమ్', 'ఐటెమ్'])) return AgentMetric.itemsAdded;
  if (has(['search', 'వెతి', 'సెర్చ్'])) return AgentMetric.searches;
  if (has(['shop', 'షాపు', 'షాప్', 'దుకాణ'])) return AgentMetric.shops;
  if (has(['product', 'ప్రొడక్ట్', 'ఉత్పత్తి'])) return AgentMetric.products;
  return null;
}

AgentPeriod periodOf(String t) {
  if (_any(t, ['yesterday', 'నిన్న', 'ninna'])) return AgentPeriod.yesterday;
  if (_any(t, ['this week', 'last 7 days', 'week', 'ఈ వారం', 'వారం'])) return AgentPeriod.week;
  if (_any(t, ['this month', 'month', 'ఈ నెల', 'నెల'])) return AgentPeriod.month;
  return AgentPeriod.today;
}

/// The first of [places] (town / district / state names) named in [text], else ''.
String placeOf(String text, List<String> places) {
  final t = agentNormalize(text);
  String? best;
  for (final p in places) {
    final n = agentNormalize(p);
    if (n.length < 3) continue;
    if (RegExp('(^|\\s)${RegExp.escape(n)}').hasMatch(t) && (best == null || n.length > agentNormalize(best).length)) best = p;
  }
  if (best != null) return best;
  // "in Narsipatnam", "Narsipatnam లో": a place not on the list yet.
  final m = RegExp(r'\bin ([A-Z][\p{L}]+)', unicode: true).firstMatch(text) ?? RegExp(r'([\p{L}]{3,})\s*(లో|లోని)\b', unicode: true).firstMatch(text);
  return m?.group(1) ?? '';
}

double? kmOf(String t) {
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*(km|kms|kilomet|కి\.?\s?మీ|కిమీ|కిలోమీటర్)').firstMatch(t);
  return m == null ? null : double.tryParse(m.group(1)!);
}

int? daysOf(String t) {
  final m = RegExp(r'(\d+)\s*(days?|రోజులు|రోజు|rojulu|roju)').firstMatch(t);
  if (m != null) return int.tryParse(m.group(1)!);
  if (_any(t, ['one day', 'ఒక రోజు', 'oka roju'])) return 1;
  if (_any(t, ['one week', 'ఒక వారం'])) return 7;
  return null;
}

int? hoursOf(String t) {
  final m = RegExp(r'(\d+)\s*(hours?|hrs?|గంటలు|గంట)').firstMatch(t);
  return m == null ? null : int.tryParse(m.group(1)!);
}

AdReach? reachOf(String t, {required bool hasPlace}) {
  if (_any(t, ['all india', 'whole india', 'అఖిల భారత', 'ఇండియా మొత్తం', 'దేశం మొత్తం', 'india mottham', 'india motham'])) return AdReach.allIndia;
  if (_any(t, ['district', 'జిల్లా'])) return AdReach.district;
  if (_any(t, ['state', 'రాష్ట్రం', 'రాష్ట్ర'])) return AdReach.state;
  if (kmOf(t) != null) return AdReach.radius;
  if (hasPlace || _any(t, ['town', 'ఊరు', 'పట్టణం'])) return AdReach.town;
  return null;
}

/// The value said with a design change: a colour name or #hex, or a number ("20", "+10", "10%", "20 px"), else ''.
String designValueOf(String t) {
  final hex = RegExp(r'#[0-9a-f]{6}\b|#[0-9a-f]{3}\b').firstMatch(t);
  if (hex != null) return hex.group(0)!;
  for (final c in agentColorNames.keys) {
    if (RegExp('(^|\\s)${RegExp.escape(c)}(\\s|\$)').hasMatch(t)) return c;
  }
  final n = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*(%|px|పిక్సెల్)?').firstMatch(t);
  return n == null ? '' : '${n.group(1)}${n.group(2) == '%' ? '%' : ''}';
}

/// Colour names the admin may say, English and Telugu, as ARGB hex.
const agentColorNames = <String, String>{
  'red': '#FFD32F2F', 'ఎరుపు': '#FFD32F2F', 'ఎర్ర': '#FFD32F2F', 'erra': '#FFD32F2F',
  'green': '#FF2E7D32', 'ఆకుపచ్చ': '#FF2E7D32', 'పచ్చ': '#FF2E7D32', 'pachha': '#FF2E7D32',
  'blue': '#FF1565C0', 'నీలం': '#FF1565C0', 'నీలి': '#FF1565C0', 'neelam': '#FF1565C0',
  'yellow': '#FFFBC02D', 'పసుపు': '#FFFBC02D', 'pasupu': '#FFFBC02D',
  'orange': '#FFEF6C00', 'నారింజ': '#FFEF6C00', 'కాషాయం': '#FFEF6C00',
  'black': '#FF000000', 'నలుపు': '#FF000000', 'నల్ల': '#FF000000',
  'white': '#FFFFFFFF', 'తెలుపు': '#FFFFFFFF', 'తెల్ల': '#FFFFFFFF',
  'pink': '#FFD81B60', 'గులాబీ': '#FFD81B60', 'purple': '#FF6A1B9A', 'ఊదా': '#FF6A1B9A',
  'grey': '#FF757575', 'gray': '#FF757575', 'బూడిద': '#FF757575', 'brown': '#FF6D4C41', 'గోధుమ': '#FF6D4C41',
};

/// Reads one command. [places] are the town / district / state names the panel knows (Business Profile towns, city codes ...).
AgentCommand parseAgentCommand(String text, {List<String> places = const []}) {
  final t = ' ${text.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  final place = placeOf(text, places);
  if (_any(t, _healthWords)) return AgentCommand(AgentIntent.health, text);
  if (_any(t, _countWords)) {
    final metric = metricOf(t);
    if (metric != null) return AgentCommand(AgentIntent.count, text, metric: metric, period: periodOf(t), place: place);
  }
  final km = kmOf(t), days = daysOf(t), hours = hoursOf(t);
  final placement = _any(t, ['right side', 'right ad', 'right box', 'ad box', 'కుడి']) ? 'rightBox' : _any(t, ['today', 'టుడే', 'ఈరోజు']) ? 'todaysOffers' : '';
  final adLike = _any(t, _adWords);
  if (adLike && _any(t, _rateWords) && _any(t, ['live', 'show', 'చూపించు', 'లైవ్'])) {
    return AgentCommand(AgentIntent.rate, text, place: place, km: km, days: days, hours: hours, reach: reachOf(t, hasPlace: place.isNotEmpty), placement: placement);
  }
  if (_any(t, ['live rate', 'live price', 'లైవ్ రేటు', 'లైవ్ ధర'])) {
    return AgentCommand(AgentIntent.rate, text, place: place, km: km, days: days, hours: hours, reach: reachOf(t, hasPlace: place.isNotEmpty), placement: placement.isEmpty ? 'todaysOffers' : placement);
  }
  if (adLike && (km != null || days != null || hours != null || _any(t, _adDetailWords))) {
    return AgentCommand(AgentIntent.ad, text, place: place, km: km, days: days, hours: hours, reach: reachOf(t, hasPlace: place.isNotEmpty), placement: placement.isEmpty ? 'todaysOffers' : placement);
  }
  if (_any(t, _designWords)) return AgentCommand(AgentIntent.design, text, value: designValueOf(t));
  return AgentCommand(AgentIntent.open, text);
}
