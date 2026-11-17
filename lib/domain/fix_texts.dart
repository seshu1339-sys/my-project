// The admin AI Agent's Telugu explanation of each problem cause and the fix it proposes (AI Agent + Health System part 4, 17 Nov
// 2026). Written here, so every issue gets an explanation for free; the "AI explain" button (Claude Haiku, only when the admin turned AI
// explain on) adds a deeper one for a single issue.

class FixText {
  const FixText(this.reason, this.fix);

  /// Why it happens, in Telugu (with the English words the admin knows).
  final String reason;

  /// What the agent will change when the admin presses Fix.
  final String fix;
}

const _fixTexts = <String, FixText>{
  'server_error': FixText('సర్వర్ ఫంక్షన్‌లో కోడ్ లోపం (code bug) వల్ల ఈ ఆప్షన్ పని చేయలేదు.', 'ఆ server function కోడ్‌లో లోపాన్ని సరిచేసి, దానికి ఒక test రాసి, server functions మళ్ళీ deploy చేస్తాను.'),
  'server_refused': FixText('Firestore rules లేదా server అనుమతి ఈ పనిని ఆపేసింది (permission).', 'సరైన వ్యక్తులకు మాత్రమే అనుమతి ఉండేలా rules / role check సరిచేసి, rules tests run చేస్తాను.'),
  'server_down': FixText('సర్వర్ ఫంక్షన్ అందుబాటులో లేదు (unavailable) — deploy లోపం లేదా Google limit.', 'ఆ function deploy స్థితి, limits చూసి, అవసరమైతే మళ్ళీ deploy చేస్తాను.'),
  'server_slow': FixText('సర్వర్ సమాధానం చాలా ఆలస్యంగా వచ్చింది (deadline exceeded).', 'ఆ function లో నెమ్మదైన పని (ఎక్కువ reads / లూప్) తగ్గించి వేగం పెంచుతాను.'),
  'sign_in_failed': FixText('లాగిన్ (Google / email code) మా వైపు లోపంతో ఆగిపోయింది.', 'లాగిన్ ప్రవాహాన్ని (store.dart / email-login.js) సరిచేసి, login tests run చేస్తాను.'),
  'upload_failed': FixText('ఫోటో అప్‌లోడ్ మా వైపు ఆగిపోయింది (Storage rules లేదా path).', 'Storage rules / upload path సరిచేసి, upload tests run చేస్తాను.'),
  'no_response': FixText('వ్యక్తి ఒకే ఆప్షన్‌ను పదే పదే నొక్కారు కానీ ఏమీ జరగలేదు — button కి పని కనెక్ట్ కాలేదు లేదా నెమ్మదిగా ఉంది.', 'ఆ button కోడ్ సరిచేసి, నొక్కగానే loading / సందేశం కనిపించేలా చేస్తాను.'),
  'hang': FixText('యాప్ కొన్ని సెకన్లు ఆగిపోయింది (hang) — ఒకేసారి చాలా పెద్ద పని main thread మీద జరిగింది.', 'ఆ పనిని నేపథ్యంలో (background) చేసేలా మార్చి, స్క్రీన్ ఆగకుండా చేస్తాను.'),
  'stuck_loading': FixText('స్క్రీన్ లోడ్ అవుతూనే ఉంది — data రాలేదు లేదా error చూపలేదు.', 'loading కి time limit పెట్టి, data రాకపోతే error / మళ్ళీ ప్రయత్నించు బటన్ చూపేలా చేస్తాను.'),
  'slow': FixText('స్క్రీన్ లేదా సేవ్ చాలా నెమ్మదిగా ఉంది.', 'ఎక్కువ data ఒకేసారి తెచ్చే చోట తగ్గించి / cache చేసి వేగం పెంచుతాను.'),
  'repeat_fail': FixText('ఒకే సేవ్ / అప్‌లోడ్ మళ్ళీ మళ్ళీ విఫలమైంది.', 'మొదటి విఫలానికి అసలు కారణం సరిచేసి, విఫలమైతే స్పష్టమైన సందేశం చూపేలా చేస్తాను.'),
  'crash': FixText('యాప్ crash అయింది (కోడ్ లోపం).', 'Crashlytics stack చూసి ఆ కోడ్ లోపాన్ని సరిచేసి, test రాస్తాను.'),
  'error': FixText('యాప్ కోడ్‌లో లోపం (error) వచ్చింది.', 'ఆ error వచ్చే చోటు సరిచేసి, test రాస్తాను.'),
  'device': FixText('ఈ సమస్య కొన్ని ఫోన్ మోడళ్లు / Android version లలో మాత్రమే వస్తోంది (device side).', 'ఆ ఫోన్ / Android version కి సరిపోయేలా కోడ్ మార్చి (compatibility), ఆ మోడల్స్‌కు ప్రత్యేక జాగ్రత్త పెడతాను.'),
};

/// The explanation and proposed fix of a problem (device side first: the phones are the reason).
FixText fixTextOf({required String side, required String cause}) =>
    side == 'device' ? _fixTexts['device']! : _fixTexts[cause] ?? const FixText('ఈ సమస్యకు కారణం కోడ్‌లో చూడాలి.', 'కారణం కనుక్కుని కోడ్ సరిచేసి, tests run చేస్తాను.');

/// What a fix changes, from the files it touches: how it goes live after the admin's OK.
///   website / admin / server   deployed at once (hosting, functions, rules)
///   design / remote config     a settings change: the apps take it at once
///   app code                   a new Android build to the Closed testing track (Google's review before people get it)
enum FixKind { website, admin, server, design, app }

const fixKindNames = <FixKind, String>{
  FixKind.website: 'Website (goes live at once)',
  FixKind.admin: 'Admin panel (goes live at once)',
  FixKind.server: 'Server functions / rules (go live at once)',
  FixKind.design: 'Design / remote config (apps take it at once)',
  FixKind.app: 'Android app code (new build to Closed testing; Google review)',
};

FixKind? fixKindOf(String name) => FixKind.values.where((k) => k.name == name).firstOrNull;

/// The steps of a fix request, in order (functions write none of them; the admin panel and the fix worker on the owner's PC do).
const fixStatuses = ['requested', 'working', 'ready', 'approved', 'deploying', 'live', 'failed', 'declined', 'undoRequested', 'undone'];

const fixStatusNames = <String, String>{
  'requested': 'Asked: waiting for the fix agent on the PC',
  'working': 'The fix agent is writing the fix and running the tests',
  'ready': 'Fix ready: check the changes and press OK',
  'approved': 'OK given: waiting to go live',
  'deploying': 'Going live…',
  'live': 'Live',
  'failed': 'Did not work',
  'declined': "Don't fix",
  'undoRequested': 'Undo asked: waiting for the fix agent',
  'undone': 'Undone (put back as before)',
};
