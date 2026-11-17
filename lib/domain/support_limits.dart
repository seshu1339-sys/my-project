// The admin's limits of the AI Agent + Health System (17 Nov 2026), each with its default and safe range. Kept in settings/health
// (problem detection and the burst alert) and settings/support (the AI Support box). Pure: no Firebase, so the apps, the admin page and
// the tests read them the same way. The server reads the same fields (functions/modules/app-problems/cases.js healthConfig).

import 'catalog.dart';

class SupportLimit {
  const SupportLimit(this.record, this.id, this.label, this.defaultValue, this.min, this.max, {this.unit = ''});
  final String record, id, label, unit;
  final num defaultValue, min, max;
}

const supportLimits = <SupportLimit>[
  SupportLimit('health', 'burstCount', 'Alert me when the same problem happens this many times', 6, 2, 1000, unit: 'times'),
  SupportLimit('health', 'burstMinutes', '…within this many minutes', 60, 5, 1440, unit: 'min'),
  SupportLimit('health', 'slowScreenSeconds', 'A screen slower than this is a problem', 2.5, 1, 30, unit: 's'),
  SupportLimit('health', 'slowSaveSeconds', 'A save / upload slower than this is a problem', 8, 2, 60, unit: 's'),
  SupportLimit('health', 'loadingSeconds', 'A screen still loading after this is stuck', 20, 5, 120, unit: 's'),
  SupportLimit('health', 'freezeSeconds', 'The app not answering for this long is a hang', 3, 1, 30, unit: 's'),
  SupportLimit('support', 'replyDays', '"We will solve it within … day(s)" in the AI Support box', 1, 1, 30, unit: 'days'),
  SupportLimit('support', 'aiDailyLimit', 'AI answers in the AI Support box per day (all people together)', 15, 0, 2000),
];

SupportLimit supportLimit(String id) => supportLimits.firstWhere((l) => l.id == id);

/// The value of one limit from the settings records (the default when not set or out of range).
num limitValue(List<Entry> settings, String id) {
  final l = supportLimit(id);
  final raw = num.tryParse('${settings.where((e) => e.id == l.record).firstOrNull?.data[id] ?? ''}');
  return raw == null || raw < l.min || raw > l.max ? l.defaultValue : raw;
}

/// settings/support.aiOn: the AI Support box may ask Claude Haiku (unknown problems and typed questions). Off by default.
bool supportAiOn(List<Entry> settings) => settings.where((e) => e.id == 'support').firstOrNull?.data['aiOn'] == true;
