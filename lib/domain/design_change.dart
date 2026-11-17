// Design changes by command (owner spec E, 17 Nov 2026): "make the search box wider", "Today's Offers రంగు ఎరుపు", "camera icon 30".
// The agent finds the exact design property (the settings registry), asks for the value, keeps it inside the safe range, warns when it may
// break the layout, shows a preview, and saves only on OK, with a history line that one tap undoes. Pure: no Firebase here.
//
//   settings/<record>.<field>    the value (website layout: section_<part>; Android app sizes: androidSizes; texts and sizes that were
//                                fixed in the code: design; Theme and Scrolling Text: their own records). The Android apps read the same
//                                settings records from the server, so a change shows without a Play Store update.
//   designHistory/<id>           {entryId, name, recordId, field, before, after, command, by, at, undone, undoneAt}
import 'agent_command.dart';
import 'agent_registry.dart';
import 'catalog.dart';

/// The design values that were fixed in the code, now in settings/design (owner spec E), with their defaults and safe ranges.
const designRecordId = 'design';

class DesignField {
  const DesignField(this.id, this.label, this.defaultValue, {this.min, this.max, this.te = const []});
  final String id, label;
  final Object defaultValue;
  final double? min, max;
  final List<String> te;
  bool get isNumber => min != null;
}

const designFields = <DesignField>[
  DesignField('rightBoxHeight', 'Right-side ad box height', 240.0, min: 120, max: 400, te: ['కుడి యాడ్ బాక్స్ ఎత్తు']),
  DesignField('todaysOfferLabel', "Today's Offers box heading text", "Today's Offer", te: ['టుడేస్ ఆఫర్ పేరు']),
  DesignField('noOfferText', "Today's Offers empty box text", 'Local vendor not updated offer', te: ['ఖాళీ బాక్స్ టెక్స్ట్']),
];

/// A number of settings/design (its default when not set; always inside its safe range).
double designNumber(List<Entry> settings, String id) {
  final f = designFields.firstWhere((x) => x.id == id);
  final v = double.tryParse('${settings.where((e) => e.id == designRecordId).firstOrNull?.data[id] ?? ''}');
  return (v ?? f.defaultValue as double).clamp(f.min!, f.max!).toDouble();
}

/// A text of settings/design (its default when not set).
String designText(List<Entry> settings, String id) {
  final v = '${settings.where((e) => e.id == designRecordId).firstOrNull?.data[id] ?? ''}'.trim();
  return v.isNotEmpty ? v : '${designFields.firstWhere((x) => x.id == id).defaultValue}';
}

/// What kind of value a property takes.
enum DesignValueKind { color, number, text, toggle }

DesignValueKind designKindOf(RegistryEntry e) {
  final f = e.field.contains('__') ? e.field.split('__').last : e.field;
  if (f.endsWith('Color') || f == 'gradientStart' || f == 'gradientEnd' || f == 'primary' || f == 'secondary') return DesignValueKind.color;
  if (f == 'visible') return DesignValueKind.toggle;
  if (e.isNumber) return DesignValueKind.number;
  return DesignValueKind.text;
}

/// The settings record and field one design property is saved in.
({String record, String field}) designTargetOf(RegistryEntry e) {
  if (e.open.startsWith('layout:')) return (record: 'section_${e.open.substring(7)}', field: e.field);
  if (e.open == 'androidSizes') return (record: 'androidSizes', field: e.field);
  if (e.open == 'designTexts') return (record: designRecordId, field: e.field);
  return (record: e.open == 'settings' ? 'business' : e.open, field: e.field);
}

/// Whether the command box treats an option as a design property (sizes, colours and texts of the look, not business settings).
bool isDesignOption(RegistryEntry e) => e.kind == RegistryKind.design || (e.kind == RegistryKind.field && const {'theme', 'scrollingText'}.contains(e.open));

/// The new value from what was said, given the current one. Words like "wider" / "bigger" / "పెద్దగా" make a number grow by the said
/// amount ("wider by 20", "20% bigger"), "narrower" / "smaller" / "చిన్నగా" shrink it; a plain number is the new value. Colour names and
/// #hex become ARGB hex. Null when the words give no value (the agent then asks).
String? proposedValue(DesignValueKind kind, String said, Object? current, {String text = ''}) {
  final t = ' ${text.toLowerCase()} ';
  if (kind == DesignValueKind.color) {
    final v = said.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (agentColorNames.containsKey(v)) return agentColorNames[v];
    final hex = v.replaceFirst('#', '');
    if (RegExp(r'^[0-9a-f]{6}$').hasMatch(hex)) return '#FF${hex.toUpperCase()}';
    if (RegExp(r'^[0-9a-f]{8}$').hasMatch(hex)) return '#${hex.toUpperCase()}';
    if (RegExp(r'^[0-9a-f]{3}$').hasMatch(hex)) return '#FF${hex.split('').map((c) => '$c$c').join().toUpperCase()}';
    return null;
  }
  if (kind == DesignValueKind.number) {
    final grow = RegExp(r'\b(wider|bigger|larger|taller|more|increase|grow)\b|పెద్ద|పెంచు|ఎక్కువ').hasMatch(t);
    final shrink = RegExp(r'\b(narrower|smaller|shorter|less|decrease|reduce)\b|చిన్న|తగ్గించు|తక్కువ').hasMatch(t);
    final cur = double.tryParse('${current ?? ''}') ?? 0;
    final m = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*(%)?').firstMatch(said.isEmpty ? t : said);
    if (m == null) {
      if (!grow && !shrink) return null;
      // "wider" with no number: a tenth more (or less), at least 2.
      final step = (cur.abs() * .1).clamp(2, double.infinity);
      return _num(cur + (grow ? step : -step));
    }
    var n = double.parse(m.group(1)!);
    final percent = m.group(2) == '%';
    final relative = percent || grow || shrink || m.group(1)!.startsWith('+') || m.group(1)!.startsWith('-') || RegExp(r'\bby\b').hasMatch(t);
    if (percent) n = cur * n.abs() / 100;
    if (!relative) return _num(n);
    if (shrink) n = -n.abs();
    if (grow) n = n.abs();
    return _num(cur + n);
  }
  if (kind == DesignValueKind.toggle) {
    if (RegExp(r'\b(hide|off|remove)\b|దాచు|తీసేయ్').hasMatch(t)) return 'false';
    if (RegExp(r'\b(show|on)\b|చూపించు').hasMatch(t)) return 'true';
    return null;
  }
  final quoted = RegExp('["“](.+?)["”]').firstMatch(text);
  if (quoted != null) return quoted.group(1);
  final to = RegExp(r'\bto\s+(.+)$', caseSensitive: false).firstMatch(text.trim());
  return to?.group(1)?.trim();
}

String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

/// The checked value: a number kept inside the safe range ("auto-fit"), with the warnings the admin sees before saving.
({String value, List<String> warnings}) fitDesignValue(RegistryEntry e, DesignValueKind kind, String value, {Object? current}) {
  final warnings = <String>[];
  if (kind == DesignValueKind.number) {
    var n = double.tryParse(value.trim());
    if (n == null) return (value: '${current ?? ''}', warnings: ['"$value" is not a number.']);
    if (e.isNumber && n < e.min!) {
      warnings.add('${_num(n)} is below the safe minimum ${_num(e.min!)}: set to ${_num(e.min!)}.');
      n = e.min!;
    }
    if (e.isNumber && n > e.max!) {
      warnings.add('${_num(n)} is above the safe maximum ${_num(e.max!)}: set to ${_num(e.max!)}.');
      n = e.max!;
    }
    final f = e.field.contains('__') ? e.field.split('__').last : e.field;
    if ((f.toLowerCase().contains('width')) && n > 1200) warnings.add('Wider than most screens: on a phone it shrinks to the screen.');
    if (f == 'fontSize' && n > 28) warnings.add('Large letters may wrap to two lines on a phone.');
    if ((f == 'height' || f == 'minHeight') && n > 600) warnings.add('Very tall: on a phone the part below moves far down.');
    final cur = double.tryParse('${current ?? ''}');
    if ((f.toLowerCase().contains('width') || f == 'height') && (cur == null || cur == 0) && n > 0) {
      warnings.add('This part sized itself before (0 = automatic); from now on it keeps ${_num(n)} px.');
    }
    return (value: _num(n), warnings: warnings);
  }
  if (kind == DesignValueKind.color) {
    final ok = RegExp(r'^#[0-9A-Fa-f]{8}$').hasMatch(value);
    return ok ? (value: value.toUpperCase(), warnings: warnings) : (value: '${current ?? ''}', warnings: ['Choose a colour (a name like red, or #RRGGBB).']);
  }
  if (kind == DesignValueKind.text) {
    final v = value.trim();
    if (v.length > 80) warnings.add('A long text may not fit in the box on a phone: it is cut to 80 letters.');
    return (value: v.length > 80 ? v.substring(0, 80) : v, warnings: warnings);
  }
  return (value: value == 'true' ? 'true' : 'false', warnings: warnings);
}

/// "Search Box › Width: 0 → 600 (Website + User app)" — what changed, in one line.
String describeChange(RegistryEntry e, Object? before, String after) {
  final was = '${before ?? ''}'.isEmpty ? '(default)' : '$before';
  return '${e.name}: $was → $after (${e.platforms.map((p) => p.label).join(' + ')})';
}

/// One line of the design history.
class DesignChange {
  const DesignChange({required this.id, required this.entryId, required this.name, required this.record, required this.field, required this.before, required this.after, this.command = '', this.at, this.undone = false});
  final String id, entryId, name, record, field, command;
  final Object? before;
  final Object after;
  final DateTime? at;
  final bool undone;

  factory DesignChange.from(String id, Map<String, dynamic> d) => DesignChange(
    id: id,
    entryId: '${d['entryId'] ?? ''}',
    name: '${d['name'] ?? ''}',
    record: '${d['recordId'] ?? ''}',
    field: '${d['field'] ?? ''}',
    before: d['before'],
    after: d['after'] ?? '',
    command: '${d['command'] ?? ''}',
    at: (() {
      try {
        final dynamic v = d['at'];
        return v == null ? null : v is DateTime ? v : v.toDate() as DateTime;
      } catch (_) {
        return null;
      }
    })(),
    undone: d['undone'] == true,
  );
}
