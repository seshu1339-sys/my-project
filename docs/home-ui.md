# Home page

The home page uses the existing green Material theme and existing Store, search providers, page routes and location flow. No Firebase configuration, authentication, backend functions, rules or GitHub configuration changes are required.

- `home_content.dart` composes categories, featured products, nearby shops, services, offers and the desktop advertising column.
- `home_widgets.dart` contains reusable category, product, shop, grid and section-heading widgets.
- `home_promotions.dart` handles the ticker, six-second carousel and scheduled promotional cards. Existing admin visibility, order, targets and size fields are used. Reduced-motion preferences stop visible automatic movement.
- `home_hero_slide.dart` renders the responsive promotional artwork and text.
- `storefront.dart` connects existing search, location, cart, account and admin actions, with bottom navigation below 700px and a right advertising column from 1100px.

Admin product editing includes an optional `compareAtPrice` for discount badges. The badge compares this against the customer's effective pincode price. Demo cards use illustrative original prices; live cards use only provided values. Product and promotional images continue to use the existing `imageUrl` fields and icon artwork when absent or unavailable.

Empty collections use presentation-only sample data. Preview products cannot open a real product page or enter the cart. Nearby shops use the existing GPS radius/pincode filtering after location is selected. Voice/image search buttons retain the existing provider integration and explanatory message if no provider is connected.

Validation covers 320px, 390px, 768px and 1440px layouts, large text, mobile navigation, disabled preview purchases, existing search/cart flows and admin editing. Rendered previews are generated under `build/home-390.png` and `build/home-1440.png` by `test/home_layout_test.dart`.
