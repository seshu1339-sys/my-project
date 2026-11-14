/// The admin panel's route map (owner, 14 Nov 2026): every page with its Telugu name and other words people say, in ONE place. The
/// search box, the voice search and the AI agent's "open ..." commands all use it (lib/ui/admin_settings.dart adminSettingsIndex), so a
/// new page needs only one line here. test/admin_routes_test.dart checks that every page of the panel has a line.
///
/// [key] is the page's key in the search index: a Settings section ('homeOffers'), an earlier main tab ('tab:Plans'), a module section
/// ('module-itemPhotos') or 'serviceProviders'.
class AdminRoute {
  const AdminRoute(this.key, this.te, [this.words = const [], this.en = '']);
  final String key;
  // The Telugu name, and other words (English or Telugu) that mean the page.
  final String te;
  final List<String> words;
  // Only for a part of a page that has no line of its own in the panel (for example the Cells tab of Staff Areas): its English name.
  final String en;

  bool get extra => en.isNotEmpty;
}

const adminRoutes = <AdminRoute>[
  // Business
  AdminRoute('tab:Insights', 'ఇన్‌సైట్స్', ['గణాంకాలు', 'dashboard', 'numbers', 'analytics']),
  AdminRoute('tab:Orders', 'ఆర్డర్లు', ['ఆర్డర్', 'order']),
  AdminRoute('tab:Support Team chat', 'సపోర్ట్ టీమ్', ['support', 'chat', 'inbox', 'చాట్', 'flash']),
  AdminRoute('aiAssistant', 'AI సహాయకుడు', ['assistant', 'ai', 'ఏఐ']),
  // Vendors & Shops
  AdminRoute('tab:Vendors', 'వెండర్లు', ['వెండర్', 'vendor', 'approve', 'ఆమోదం']),
  AdminRoute('tab:Shops', 'షాపులు', ['షాప్', 'దుకాణాలు', 'shop']),
  AdminRoute('tab:Products', 'ఉత్పత్తులు', ['ప్రొడక్ట్స్', 'items', 'ఐటమ్స్', 'product']),
  AdminRoute('categories', 'కేటగిరీలు', ['కేటగిరీ', 'category', 'వర్గాలు']),
  AdminRoute('productImageLibrary', 'ఐటమ్ కేటలాగ్', ['catalog', 'కేటలాగ్', 'image library', 'photos', 'ఫోటోలు']),
  AdminRoute('shopsLocation', 'లొకేషన్ లేని షాపులు', ['location', 'లొకేషన్']),
  AdminRoute('cityCodes', 'సిటీ కోడ్స్', ['city code', 'ఊరి కోడ్']),
  AdminRoute('tab:Plans', 'ప్లాన్స్', ['ప్లాన్', 'plan', 'subscription', 'gold', 'diamond', 'platinum', 'silver']),
  AdminRoute('tab:Premium', 'ప్రీమియం', ['wholesale', 'హోల్‌సేల్', 'vendor today offers', 'వెండర్ ఆఫర్ బాక్సులు']),
  AdminRoute('tab:Payments', 'చెల్లింపులు', ['పేమెంట్స్', 'payment', 'razorpay']),
  AdminRoute('tab:Complaints', 'ఫిర్యాదులు', ['complaint', 'కంప్లైంట్']),
  AdminRoute('ratings', 'రేటింగ్స్', ['stars', 'నక్షత్రాలు', 'rating']),
  AdminRoute('reports', 'రిపోర్టులు', ['abuse', 'ఫిర్యాదు రిపోర్ట్', 'report']),
  AdminRoute('blockList', 'బ్లాక్ లిస్ట్', ['block', 'బ్లాక్']),
  AdminRoute('module-itemPhotos', 'ఐటమ్ ఫోటోలు', ['item photo', 'own photo', 'add to catalog']),
  // Services
  AdminRoute('services', 'సేవలు', ['సర్వీసులు', 'service types']),
  AdminRoute('serviceProviders', 'సర్వీస్ ప్రొవైడర్లు', ['providers', 'ప్రొవైడర్']),
  AdminRoute('module-transport', 'రవాణా', ['ట్రాన్స్‌పోర్ట్', 'transport', 'auto', 'ఆటో']),
  // Staff
  AdminRoute('fieldAssistants', 'స్టాఫ్ ఆమోదం', ['స్టాఫ్', 'staff', 'field assistants', 'ఫీల్డ్']),
  AdminRoute('tab:Staff Areas', 'స్టాఫ్ ఏరియాలు', ['ఏరియా', 'area', 'staff area']),
  AdminRoute('tab:Staff Areas', 'సెల్స్', ['సెల్', 'cell', 'hexagon', 'హెక్సాగన్', 'కణాలు', 'staff cells'], 'Cells'),
  AdminRoute('staffWork', 'స్టాఫ్ పని, జీతం', ['pay', 'జీతం', 'work', 'పని']),
  AdminRoute('staffRanking', 'స్టాఫ్ ర్యాంకింగ్', ['ranking', 'ర్యాంక్']),
  AdminRoute('idReport', 'ID రిపోర్ట్', ['ఐడి రిపోర్ట్', 'id']),
  AdminRoute('staffLinks', 'స్టాఫ్ లింకులు', ['లింక్', 'link', 'requests', 'అభ్యర్థనలు']),
  AdminRoute('locations', 'క్విక్ యాడ్ ప్రదేశాలు', ['quick add', 'locations']),
  // Ads & Offers
  AdminRoute('tab:Promotions', 'ప్రమోషన్లు', ['promotion', 'ప్రమోషన్']),
  AdminRoute('tab:Vendor Offers', 'వెండర్ ఆఫర్లు', ['vendor offer', 'offer alerts']),
  AdminRoute('homeOffers', 'టుడేస్ ఆఫర్', ["today's offer", 'todays offer', 'today offer', 'ఈరోజు ఆఫర్లు', 'ఆఫర్']),
  AdminRoute('homePromo', 'టుడేస్ ఆఫర్ బాక్స్', ['offer box', 'ఆఫర్ బాక్స్', 'బాక్సులు']),
  AdminRoute('homeFresh', 'పండ్లు కూరగాయలు', ['fresh', 'fruits', 'vegetables', 'ఫ్రెష్']),
  AdminRoute('scrollingText', 'స్క్రోలింగ్ టెక్స్ట్', ['moving text', 'కదిలే లైన్']),
  AdminRoute('ads', 'యాడ్స్', ['ads', 'ప్రకటనలు', 'advert']),
  AdminRoute('rightBoxes', 'యాడ్ బాక్సులు', ['ad boxes', 'right boxes']),
  // Settings
  AdminRoute('settings', 'బిజినెస్ ప్రొఫైల్', ['business', 'profile', 'సెట్టింగ్స్', 'settings', 'auto approval']),
  AdminRoute('theme', 'థీమ్', ['colours', 'colors', 'రంగులు']),
  AdminRoute('animations', 'యానిమేషన్లు', ['animation']),
  AdminRoute('layout', 'లేఅవుట్', ['design', 'డిజైన్']),
  AdminRoute('androidHome', 'ఆండ్రాయిడ్ యాప్', ['android', 'app']),
  AdminRoute('areaNames', 'ఏరియా పేర్లు', ['area names', 'place names', 'ప్రదేశాల పేర్లు']),
  AdminRoute('samples', 'శాంపిల్ డేటా', ['sample', 'demo']),
];

/// Every word a page is known by, besides its English title (the route map lines with this key that are not extra parts).
String adminRouteAliases(String key) => [
  for (final r in adminRoutes)
    if (r.key == key && !r.extra) ...[r.te, ...r.words],
].join(' | ');

/// Words that only say "open" / "show" (English and Telugu); they are left out before the page is looked for.
const _commandWords = ['open', 'show', 'go to', 'goto', 'take me to', 'page', 'please', 'తెరువు', 'తెరవు', 'ఓపెన్', 'చూపించు', 'చూపు', 'చూపండి', 'తెరవండి', 'కు వెళ్ళు', 'వెళ్ళు', 'పేజీ', 'పేజ్', 'ని', 'కి'];

/// The page words in what was typed or said: "Cells తెరువు" -> "cells", "open the plans page" -> "plans".
String adminCommandQuery(String text) {
  var q = ' ${text.toLowerCase().replaceAll(RegExp(r'[.,!?।]'), ' ')} ';
  for (final w in _commandWords) {
    q = q.replaceAll(' $w ', ' ');
  }
  q = q.replaceAll(RegExp(r'\s(the|a)\s'), ' ');
  return q.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// True when the text asks to open or show something ("Cells తెరువు", "show plans"): a command word was taken out of it.
bool adminAsksToOpen(String text) {
  final plain = text.toLowerCase().replaceAll(RegExp(r'[.,!?।]'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
  return adminCommandQuery(text) != plain;
}
