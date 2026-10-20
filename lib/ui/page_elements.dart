/// Master "element number" registry for the admin's numbered "Go to
/// number" search and the on-preview number badges (see visual_editor.dart,
/// visual_editor_overlay.dart). Each entry's `key` is the exact
/// `layoutComponents` key (lib/ui/layout_settings.dart) that number opens.
///
/// These are whole-number, standalone or group-main elements only. A
/// repeating group's own members (one ad, one category, one carousel
/// slide, one promotional box, one footer badge, one cross-sell product)
/// are NOT listed here -- they're never stored, always computed fresh
/// (element_groups.dart's `elementGroups`/`resolveSubKey`: from the
/// group's own collection `order` for a dynamic group, or from a fixed
/// position for a static one like footer badges), so a newly added item
/// automatically gets the next sub-number ("15.3") and nothing already
/// numbered ever shifts. A group's own main number here (15, 16, 23, 24,
/// 25, 28) controls ONLY the shared template -- above all, SIZE, so every
/// item in that group is always exactly the same size; each item's own
/// number (opened via GroupItemDesignForm, or its own LayoutFieldsForm for
/// a static group) controls color, image, brightness and text style for
/// that one item, never size.
///
/// Numbers are permanent once assigned here, with one disclosed exception:
/// numbers 23 onward were corrected/renumbered once, to fix a mismatch
/// this file never actually had (23='ads'/24='boxes' was always right
/// here) but element_groups.dart did (it used 24/25), and to make room for
/// 'crossSellStrip' (25, newly added) and the 'footerBadges' group (28,
/// replacing the 6 formerly-independent footerBadge1..6 numbers 27-32).
/// From this point on, a later round only ever appends after the highest
/// existing number.
class PageElement {
  const PageElement(this.number, this.key, this.label);
  final int number;
  final String key;
  final String label;
}

const pageElements = <PageElement>[
  PageElement(1, 'logo', 'Logo'),
  PageElement(2, 'title', 'Local Market title'),
  PageElement(3, 'tagline', 'Tagline'),
  PageElement(4, 'user', 'Welcome text'),
  PageElement(5, 'location', 'Choose your location'),
  PageElement(6, 'search', 'Search box'),
  PageElement(7, 'services', 'Services icon'),
  PageElement(8, 'notificationIcon', 'Notifications icon'),
  PageElement(9, 'wishlistIcon', 'Wishlist icon'),
  PageElement(10, 'cartIcon', 'Shopping bag icon'),
  PageElement(11, 'menuIcon', 'Menu icon'),
  PageElement(12, 'office', 'Office address & phone'),
  // --- Home page, remaining sections (round 2) ---
  PageElement(13, 'notice', "Today's Best Offers strip"),
  PageElement(14, 'tickerMarquee', 'Ticker marquee banner'),
  PageElement(
    15,
    'promo',
    'Offers banner carousel (group — see 15.1, 15.2, ...)',
  ),
  PageElement(
    16,
    'categories',
    'Categories section (group — see 16.1, 16.2, ...)',
  ),
  PageElement(17, 'moreCategoriesTile', '"More Categories" tile'),
  PageElement(18, 'popular', 'Popular Products section'),
  PageElement(19, 'popularFilterChips', 'Popular Products filter chips'),
  PageElement(20, 'products', 'Product card template'),
  PageElement(21, 'localServices', 'Local Services section'),
  PageElement(22, 'adsLabel', '"ADS" label'),
  PageElement(
    23,
    'ads',
    'Advertisement box template (group — see 23.1, 23.2, ...)',
  ),
  PageElement(
    24,
    'boxes',
    'Promotional box template (group — see 24.1, 24.2, ...)',
  ),
  PageElement(
    25,
    'crossSellStrip',
    'Fresh Fruits & Vegetables strip (group — see 25.1, 25.2, ...)',
  ),
  PageElement(26, 'nearby', 'Nearby shops section'),
  PageElement(27, 'nearbyShopCard', 'Nearby shop card'),
  PageElement(
    28,
    'footerBadges',
    'Footer badges (group — see 28.1 .. 28.6)',
  ),
  // --- Other screens (round 3) -- no live preview exists for these (the
  // admin Visual Editor only ever renders the home page), so these are
  // reachable only via "Go to number" and the Layout Settings dropdown,
  // not by clicking in a live preview, and the "Show numbers" overlay has
  // nothing to draw a badge on for them. ---
  PageElement(29, 'productPageAddButton', 'Product page: "Add to bag" button'),
  PageElement(30, 'productPageBuyButton', 'Product page: "Buy now" button'),
  PageElement(31, 'productPageShareIcon', 'Product page: share icon'),
  PageElement(32, 'productPageWishlistIcon', 'Product page: wishlist icon'),
  PageElement(
    33,
    'productPageRelatedHeading',
    'Product page: "Related products" heading',
  ),
  PageElement(
    34,
    'productPageReviewsHeading',
    'Product page: "Community reviews" heading',
  ),
  PageElement(35, 'categoryPageHeading', 'Category page: section headings'),
  PageElement(36, 'cartEmptyMessage', 'Cart: empty-bag message'),
  PageElement(37, 'cartEmptyIcon', 'Cart: empty-bag icon'),
  PageElement(38, 'cartSubmitButton', 'Cart: submit order button'),
  PageElement(39, 'servicesPageAppBarTitle', 'Services page: title'),
  PageElement(40, 'shopsPageAppBarTitle', 'Shops page: title'),
  PageElement(41, 'shopsPageHeading', 'Shops page: heading'),
  PageElement(
    42,
    'shopPageDirectionsButton',
    'Shop page: "Get directions" button',
  ),
  PageElement(
    43,
    'shopPageRelatedHeading',
    'Shop page: "From this shop" heading',
  ),
  PageElement(44, 'accountPageAppBarTitle', 'Account page: title'),
  PageElement(45, 'accountDemoHeading', 'Account page: demo-mode heading'),
  PageElement(
    46,
    'accountOrdersHeading',
    'Account page: "Your orders" heading',
  ),
  PageElement(47, 'authFormHeading', 'Sign-in form: heading'),
  PageElement(48, 'wishlistDialogTitle', 'Wishlist dialog: title'),
];

PageElement? pageElementByNumber(int number) =>
    pageElements.where((e) => e.number == number).firstOrNull;
PageElement? pageElementByKey(String key) =>
    pageElements.where((e) => e.key == key).firstOrNull;

/// "3 – Welcome text" when [key] has a number yet, otherwise just the plain
/// [fallbackLabel] -- used anywhere a component's label is shown in the
/// admin so numbered elements are instantly recognizable without changing
/// the label of every not-yet-numbered section.
String numberedLabel(String key, String fallbackLabel) {
  final element = pageElementByKey(key);
  return element == null ? fallbackLabel : '${element.number} – $fallbackLabel';
}
