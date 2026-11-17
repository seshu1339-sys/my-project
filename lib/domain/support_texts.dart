// The words of the AI Support box (AI Agent + Health System part 3, 17 Nov 2026): for each cause the person can fix, "Your problem
// is: …", the steps and the one-tap fix; for our-side and device-side problems, the "we have sent it to our team" message; and the box's
// own buttons. English, Telugu and Hindi are written here (free, no AI); the app's other languages show English, and a typed question is
// answered by AI in the person's own language when the admin turned AI on.

/// A one-tap fix in the box.
enum SupportFix { locationSettings, appSettings, loginAgain, tryAgain, none }

class SupportHelp {
  const SupportHelp(this.problem, this.steps, this.fix, this.fixLabel);
  final String problem;
  final List<String> steps;
  final SupportFix fix;
  final String fixLabel;
}

const supportLanguages = ['en', 'te', 'hi'];
String supportLang(String code) => supportLanguages.contains(code) ? code : 'en';

const _help = <String, Map<String, SupportHelp>>{
  'offline': {
    'en': SupportHelp('Your phone is not connected to the internet.', ['Turn on mobile data or Wi-Fi.', 'Wait until the signal bars show.', 'Tap "Try again".'], SupportFix.tryAgain, 'Try again'),
    'te': SupportHelp('మీ ఫోన్‌కు ఇంటర్నెట్ కనెక్షన్ లేదు.', ['మొబైల్ డేటా లేదా Wi-Fi ఆన్ చేయండి.', 'సిగ్నల్ వచ్చే వరకు ఆగండి.', '"మళ్ళీ ప్రయత్నించండి" నొక్కండి.'], SupportFix.tryAgain, 'మళ్ళీ ప్రయత్నించండి'),
    'hi': SupportHelp('आपका फ़ोन इंटरनेट से जुड़ा नहीं है।', ['मोबाइल डेटा या Wi-Fi चालू करें।', 'सिग्नल आने तक रुकें।', '"फिर से कोशिश करें" दबाएँ।'], SupportFix.tryAgain, 'फिर से कोशिश करें'),
  },
  'slow_internet': {
    'en': SupportHelp('Your internet is very slow right now.', ['Move to a place with a better signal, or switch to Wi-Fi.', 'Close other apps that are downloading.', 'Tap "Try again".'], SupportFix.tryAgain, 'Try again'),
    'te': SupportHelp('ప్రస్తుతం మీ ఇంటర్నెట్ చాలా నెమ్మదిగా ఉంది.', ['సిగ్నల్ బాగా ఉన్న చోటుకు వెళ్ళండి, లేదా Wi-Fi వాడండి.', 'డౌన్‌లోడ్ చేస్తున్న ఇతర యాప్‌లు మూసేయండి.', '"మళ్ళీ ప్రయత్నించండి" నొక్కండి.'], SupportFix.tryAgain, 'మళ్ళీ ప్రయత్నించండి'),
    'hi': SupportHelp('अभी आपका इंटरनेट बहुत धीमा है।', ['अच्छे सिग्नल वाली जगह जाएँ या Wi-Fi चलाएँ।', 'डाउनलोड कर रहे दूसरे ऐप बंद करें।', '"फिर से कोशिश करें" दबाएँ।'], SupportFix.tryAgain, 'फिर से कोशिश करें'),
  },
  'location_off': {
    'en': SupportHelp('Location (GPS) is off on your phone.', ['Tap "Turn on location".', 'Switch on "Use location".', 'Come back to the app.'], SupportFix.locationSettings, 'Turn on location'),
    'te': SupportHelp('మీ ఫోన్‌లో లొకేషన్ (GPS) ఆఫ్‌లో ఉంది.', ['"లొకేషన్ ఆన్ చేయండి" నొక్కండి.', '"Use location" ఆన్ చేయండి.', 'యాప్‌కు తిరిగి రండి.'], SupportFix.locationSettings, 'లొకేషన్ ఆన్ చేయండి'),
    'hi': SupportHelp('आपके फ़ोन में लोकेशन (GPS) बंद है।', ['"लोकेशन चालू करें" दबाएँ।', '"Use location" चालू करें।', 'ऐप पर वापस आएँ।'], SupportFix.locationSettings, 'लोकेशन चालू करें'),
  },
  'location_denied': {
    'en': SupportHelp('The app is not allowed to use your location.', ['Tap "Allow permission".', 'Open "Permissions" > "Location".', 'Choose "Allow while using the app" and come back.'], SupportFix.appSettings, 'Allow permission'),
    'te': SupportHelp('మీ లొకేషన్ వాడటానికి యాప్‌కు అనుమతి లేదు.', ['"అనుమతి ఇవ్వండి" నొక్కండి.', '"Permissions" > "Location" తెరవండి.', '"Allow while using the app" ఎంచుకుని తిరిగి రండి.'], SupportFix.appSettings, 'అనుమతి ఇవ్వండి'),
    'hi': SupportHelp('ऐप को आपकी लोकेशन इस्तेमाल करने की अनुमति नहीं है।', ['"अनुमति दें" दबाएँ।', '"Permissions" > "Location" खोलें।', '"Allow while using the app" चुनें और वापस आएँ।'], SupportFix.appSettings, 'अनुमति दें'),
  },
  'permission_denied': {
    'en': SupportHelp('The app needs a permission you turned off (camera, photos or notifications).', ['Tap "Allow permission".', 'Open "Permissions".', 'Allow what is needed and come back.'], SupportFix.appSettings, 'Allow permission'),
    'te': SupportHelp('మీరు ఆపేసిన అనుమతి (కెమెరా, ఫోటోలు లేదా నోటిఫికేషన్లు) యాప్‌కు కావాలి.', ['"అనుమతి ఇవ్వండి" నొక్కండి.', '"Permissions" తెరవండి.', 'కావలసినది అనుమతించి తిరిగి రండి.'], SupportFix.appSettings, 'అనుమతి ఇవ్వండి'),
    'hi': SupportHelp('ऐप को एक अनुमति चाहिए जो आपने बंद की है (कैमरा, फ़ोटो या नोटिफ़िकेशन)।', ['"अनुमति दें" दबाएँ।', '"Permissions" खोलें।', 'ज़रूरी अनुमति दें और वापस आएँ।'], SupportFix.appSettings, 'अनुमति दें'),
  },
  'photo_too_big': {
    'en': SupportHelp('The photo is too big to upload.', ['Choose a smaller photo, or take the photo again with the app camera.', 'Crop it if you can.', 'Upload again.'], SupportFix.none, ''),
    'te': SupportHelp('ఫోటో అప్‌లోడ్ చేయడానికి చాలా పెద్దదిగా ఉంది.', ['చిన్న ఫోటో ఎంచుకోండి, లేదా యాప్ కెమెరాతో మళ్ళీ తీయండి.', 'వీలైతే క్రాప్ చేయండి.', 'మళ్ళీ అప్‌లోడ్ చేయండి.'], SupportFix.none, ''),
    'hi': SupportHelp('फ़ोटो अपलोड करने के लिए बहुत बड़ी है।', ['छोटी फ़ोटो चुनें, या ऐप के कैमरे से फिर से लें।', 'हो सके तो क्रॉप करें।', 'फिर से अपलोड करें।'], SupportFix.none, ''),
  },
  'session_expired': {
    'en': SupportHelp('Your sign-in has expired.', ['Tap "Login again".', 'Sign in with the same account.', 'Try the option again.'], SupportFix.loginAgain, 'Login again'),
    'te': SupportHelp('మీ లాగిన్ గడువు ముగిసింది.', ['"మళ్ళీ లాగిన్ అవ్వండి" నొక్కండి.', 'అదే అకౌంట్‌తో లాగిన్ అవ్వండి.', 'ఆప్షన్‌ను మళ్ళీ ప్రయత్నించండి.'], SupportFix.loginAgain, 'మళ్ళీ లాగిన్ అవ్వండి'),
    'hi': SupportHelp('आपका लॉगिन समाप्त हो गया है।', ['"फिर से लॉगिन करें" दबाएँ।', 'उसी अकाउंट से लॉगिन करें।', 'विकल्प फिर से आज़माएँ।'], SupportFix.loginAgain, 'फिर से लॉगिन करें'),
  },
  'missing_field': {
    'en': SupportHelp('Some details are missing or not filled correctly.', ['Look for the field marked in red.', 'Fill it in (for example the price, name or photo).', 'Tap the save button again.'], SupportFix.none, ''),
    'te': SupportHelp('కొన్ని వివరాలు లేవు లేదా సరిగా నింపలేదు.', ['ఎరుపు రంగులో చూపిన ఫీల్డ్ చూడండి.', 'దాన్ని నింపండి (ఉదా: ధర, పేరు లేదా ఫోటో).', 'సేవ్ బటన్ మళ్ళీ నొక్కండి.'], SupportFix.none, ''),
    'hi': SupportHelp('कुछ जानकारी छूट गई है या सही नहीं भरी गई।', ['लाल रंग में दिखाया गया फ़ील्ड देखें।', 'उसे भरें (जैसे कीमत, नाम या फ़ोटो)।', 'सेव बटन फिर से दबाएँ।'], SupportFix.none, ''),
  },
  'wrong_code': {
    'en': SupportHelp('The code you typed is not correct.', ['Open the latest email from LocaMarket.', 'Type the 6 digits exactly as shown.', 'If it is old, ask for a new code.'], SupportFix.none, ''),
    'te': SupportHelp('మీరు టైప్ చేసిన కోడ్ సరైనది కాదు.', ['LocaMarket నుండి వచ్చిన కొత్త ఈమెయిల్ తెరవండి.', 'అందులోని 6 అంకెలు సరిగ్గా టైప్ చేయండి.', 'అది పాతదైతే కొత్త కోడ్ అడగండి.'], SupportFix.none, ''),
    'hi': SupportHelp('आपने जो कोड लिखा वह सही नहीं है।', ['LocaMarket का सबसे नया ईमेल खोलें।', '6 अंक ठीक वैसे ही लिखें।', 'पुराना हो तो नया कोड माँगें।'], SupportFix.none, ''),
  },
  'code_expired': {
    'en': SupportHelp('The code has expired.', ['Tap "Use a different email or send a new code".', 'Open the new email.', 'Type the new 6-digit code within 10 minutes.'], SupportFix.none, ''),
    'te': SupportHelp('కోడ్ గడువు ముగిసింది.', ['"కొత్త కోడ్ పంపండి" నొక్కండి.', 'కొత్త ఈమెయిల్ తెరవండి.', '10 నిమిషాల్లో కొత్త 6 అంకెల కోడ్ టైప్ చేయండి.'], SupportFix.none, ''),
    'hi': SupportHelp('कोड की समय-सीमा खत्म हो गई है।', ['"नया कोड भेजें" दबाएँ।', 'नया ईमेल खोलें।', '10 मिनट के अंदर नया 6 अंकों का कोड लिखें।'], SupportFix.none, ''),
  },
  'too_many_tries': {
    'en': SupportHelp('Too many tries in a short time.', ['Wait a few minutes.', 'Then try once more, slowly.', 'If it still fails, tap "No" below and we will help.'], SupportFix.none, ''),
    'te': SupportHelp('తక్కువ సమయంలో చాలా సార్లు ప్రయత్నించారు.', ['కొన్ని నిమిషాలు ఆగండి.', 'తర్వాత నెమ్మదిగా ఒకసారి ప్రయత్నించండి.', 'అయినా రాకపోతే క్రింద "లేదు" నొక్కండి, మేము సహాయం చేస్తాం.'], SupportFix.none, ''),
    'hi': SupportHelp('कम समय में बहुत बार कोशिश की गई।', ['कुछ मिनट रुकें।', 'फिर एक बार धीरे से कोशिश करें।', 'फिर भी न हो तो नीचे "नहीं" दबाएँ, हम मदद करेंगे।'], SupportFix.none, ''),
  },
};

/// The pre-written help for a user-side [cause] in [lang] (English when that language is not written), or null for an unknown cause.
SupportHelp? supportHelp(String cause, String lang) => _help[cause]?[supportLang(lang)] ?? _help[cause]?['en'];

/// The box's own words.
const _words = <String, Map<String, String>>{
  'title': {'en': 'AI Support', 'te': 'AI సహాయం', 'hi': 'AI सहायता'},
  'yourProblem': {'en': 'Your problem is:', 'te': 'మీ సమస్య:', 'hi': 'आपकी समस्या:'},
  'step': {'en': 'Step', 'te': 'దశ', 'hi': 'चरण'},
  'solved?': {'en': 'Did this solve it?', 'te': 'ఇది పరిష్కరించిందా?', 'hi': 'क्या इससे समस्या हल हुई?'},
  'yes': {'en': 'Yes', 'te': 'అవును', 'hi': 'हाँ'},
  'no': {'en': 'No, send to team', 'te': 'లేదు, టీమ్‌కు పంపండి', 'hi': 'नहीं, टीम को भेजें'},
  'ours': {
    'en': 'We understood the problem you faced while using our app. We have sent it to our LocaMarket team and will solve it within {days}.',
    'te': 'మా యాప్ వాడుతున్నప్పుడు మీకు వచ్చిన సమస్యను మేము అర్థం చేసుకున్నాము. దాన్ని మా LocaMarket టీమ్‌కు పంపాము, {days}లో పరిష్కరిస్తాము.',
    'hi': 'हमारे ऐप का उपयोग करते समय आपको जो समस्या आई, उसे हमने समझ लिया है। हमने इसे LocaMarket टीम को भेज दिया है और {days} में हल कर देंगे।',
  },
  'day': {'en': '1 day', 'te': '1 రోజు', 'hi': '1 दिन'},
  'days': {'en': '{n} days', 'te': '{n} రోజుల', 'hi': '{n} दिन'},
  'tellMore': {'en': 'Tell us more (optional)', 'te': 'మరింత చెప్పండి (ఐచ్ఛికం)', 'hi': 'और बताएँ (वैकल्पिक)'},
  'ask': {'en': 'Or type your question', 'te': 'లేదా మీ ప్రశ్న టైప్ చేయండి', 'hi': 'या अपना सवाल लिखें'},
  'send': {'en': 'Send', 'te': 'పంపండి', 'hi': 'भेजें'},
  'askButton': {'en': 'Ask', 'te': 'అడగండి', 'hi': 'पूछें'},
  'screenshot': {'en': 'Add screenshot', 'te': 'స్క్రీన్‌షాట్ జత చేయండి', 'hi': 'स्क्रीनशॉट जोड़ें'},
  'sent': {'en': 'Sent', 'te': 'పంపబడింది', 'hi': 'भेजा गया'},
  'seen': {'en': 'Seen', 'te': 'చూశారు', 'hi': 'देखा गया'},
  'solved': {'en': 'Solved', 'te': 'పరిష్కరించబడింది', 'hi': 'हल हो गया'},
  'status': {'en': 'Status', 'te': 'స్థితి', 'hi': 'स्थिति'},
  'thanks': {'en': 'Thank you. Our team has it.', 'te': 'ధన్యవాదాలు. మా టీమ్‌కు అందింది.', 'hi': 'धन्यवाद। हमारी टीम को मिल गया।'},
  'myReports': {'en': 'My problem reports', 'te': 'నా సమస్యల రిపోర్టులు', 'hi': 'मेरी समस्या रिपोर्ट'},
  'reply': {'en': 'LocaMarket team:', 'te': 'LocaMarket టీమ్:', 'hi': 'LocaMarket टीम:'},
  'aiOff': {'en': 'Your question was sent to our team. They will answer here.', 'te': 'మీ ప్రశ్న మా టీమ్‌కు పంపబడింది. వారు ఇక్కడ సమాధానం ఇస్తారు.', 'hi': 'आपका सवाल हमारी टीम को भेज दिया गया। वे यहीं जवाब देंगे।'},
  'none': {'en': 'No reports yet.', 'te': 'ఇంకా రిపోర్టులు లేవు.', 'hi': 'अभी कोई रिपोर्ट नहीं।'},
  'newReply': {'en': 'LocaMarket team replied to your problem', 'te': 'మీ సమస్యకు LocaMarket టీమ్ సమాధానం ఇచ్చింది', 'hi': 'LocaMarket टीम ने आपकी समस्या का जवाब दिया'},
  'open': {'en': 'Open', 'te': 'తెరవండి', 'hi': 'खोलें'},
  'close': {'en': 'Close', 'te': 'మూసివేయండి', 'hi': 'बंद करें'},
};

/// One of the box's words in [lang] (English when not written).
String supportWord(String key, String lang) => _words[key]?[supportLang(lang)] ?? _words[key]?['en'] ?? key;

/// "We understood the problem … within 1 day." with the admin's number of days (settings/support.replyDays).
String supportOursMessage(String lang, int days) {
  final span = days == 1 ? supportWord('day', lang) : supportWord('days', lang).replaceAll('{n}', '$days');
  return supportWord('ours', lang).replaceAll('{days}', span);
}

/// The status word: Sent, Seen or Solved.
String supportStatus(String status, String lang) => supportWord(const ['sent', 'seen', 'solved'].contains(status) ? status : 'sent', lang);
