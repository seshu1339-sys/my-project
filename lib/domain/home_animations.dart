/// Every animation an admin can give a part of the home page, in the order the dropdowns list them. One list for all of them: the same
/// choice means the same movement whether it is the Scrolling Text, Today's Offers, Today's Offers Box or Right Side Ads.
const homeAnimations = <String, String>{
  'fade': 'Fade',
  'slide': 'Slide',
  'zoom': 'Zoom',
  'bounce': 'Bounce',
  'flip': 'Flip',
  'rotate': 'Rotate',
  'pulse': 'Pulse',
  'shake': 'Shake',
  'typewriter': 'Typewriter',
  'marquee': 'Marquee',
  'slideUp': 'Slide Up',
  'slideDown': 'Slide Down',
  'zoomIn': 'Zoom In',
  'zoomOut': 'Zoom Out',
  'none': 'None',
};

/// Older values still stored on some records, shown by their new name.
const legacyAnimations = <String, String>{'slideLeft': 'Slide', 'cube': '3D cube'};

/// The simple animation each section starts with until the admin chooses another (Settings > Homepage sections).
const homeSectionDefaults = <String, String>{
  'scrollingText': 'marquee',
  'notice': 'fade', // Today's Offers
  'promo': 'slideUp', // Today's Offers Box
  'boxes': 'fade', // Right Side Ads: the boxes below the ads
  'ads': 'fade', // Right Side Ads
};
