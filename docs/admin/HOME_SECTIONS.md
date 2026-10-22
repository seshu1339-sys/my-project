# Homepage sections (Settings)

Four parts of the customer home page have their own page in Settings, named the way the customer sees them. Each page has a small live preview
that plays the chosen animation, the animation list, the speed and the colours. They write to the records the website already reads, so the older
pages (Animations, Layout, Scrolling Text, Promotions) keep working and show the same values.

| On the website | Settings page | Records |
|---|---|---|
| The red moving line at the top | **Scrolling Text** | `settings/scrollingText` (colours, scroll speed), animation `scrollingText_type` in `settings/animations` |
| The banner "Today's <town> Offers" with the price chips (the town follows the customer's location) | **Today's Offers** | layout `section_notice` (colours), `notice_type` / `notice_speed` |
| The row of coloured boxes ("Today's Offer ...") | **Today's Offers Box** | layout `section_promo`, `promo_type` / `promo_speed`; items = promotions placed as carousel |
| The boxes down the right-hand side | **Right Side Ads** (+ "Boxes below the ads" block) | `settings/adsConfig` (animation, speed, colours); boxes: layout `section_boxes`, `boxes_type` |

## Animations
One list for every section (`lib/domain/home_animations.dart`): Fade, Slide, Zoom, Bounce, Flip, Rotate, Pulse, Shake, Typewriter, Marquee, Slide Up,
Slide Down, Zoom In, Zoom Out, None. On a section they play when it appears (Pulse, Shake and Marquee keep repeating); on the Right Side Ads they are
the change from one ad to the next. For the Scrolling Text, Marquee is the strip's own scrolling; any other choice plays on it as it appears.
Start values until the admin chooses another: Scrolling Text = Marquee, Today's Offers = Fade, Today's Offers Box = Slide Up, Right Side Ads = Fade,
boxes below the ads = Fade. Settings > Animations still has the global on/off switch and per-part choices (same records).
