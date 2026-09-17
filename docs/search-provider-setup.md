# Voice and image search setup

The current icons are wired to `SmartSearch` in `lib/services/search.dart`. Both providers are currently null. Enabling a cloud API alone will not activate them: provider adapters and backend endpoints must also be implemented and injected into `Storefront`. No paid APIs, billing settings, deployments, or credentials were changed during Chrome verification.

## Recommended provider path

Use Google Cloud Speech-to-Text for voice and Cloud Vision labels/OCR for images, called through Firebase callable functions. This fits the existing Firebase project `e-commerce-app-a3897` and its current functions region, `us-central1`.

1. In Google Cloud Console, select **e-commerce-app-a3897**. Confirm billing, review service pricing, and enable **Cloud Speech-to-Text API** and **Cloud Vision API**. Set usage quotas and budget alerts appropriate to the shop. See [Speech-to-Text overview](https://docs.cloud.google.com/speech-to-text/docs/overview) and [Vision setup](https://docs.cloud.google.com/vision/docs/setup).
2. Use the deployed function's runtime service account and Application Default Credentials for server-side Google API access. Grant the required service permissions. Do not put a service-account JSON file or private provider credential in Flutter, `web/`, or a dart-define: web builds are downloadable by visitors.
3. Add two callable endpoints to the existing functions code, for example `transcribeSearch` and `describeSearchImage`. These names are proposed, not deployed endpoints. Validate payloads and apply authentication/App Check and rate limits appropriate to whether guest shopping remains supported. Firebase callables can carry authentication and App Check tokens automatically; token availability alone is not an authorization policy. See [Firebase callable functions](https://firebase.google.com/docs/functions/callable).
4. Implement `VoiceSearchProvider.transcribe()`: request microphone access only after the user presses the icon, capture a short recording, send its actual audio encoding/sample rate and chosen language to the callable, and return the recognized search phrase. Use HTTPS in deployment or localhost in Chrome. Handle denied microphone access, cancellation, silence and timeouts while keeping typed search usable. Choose language/model/region combinations from the [supported-language table](https://docs.cloud.google.com/speech-to-text/docs/v1/speech-to-text-supported-languages); do not assume every Indian language has identical model support.
5. Implement `ImageSearchProvider.describe(Uint8List bytes)`: send the selected image to the callable for labels and, when useful, package-text recognition. Keep the existing 5 MB client guard and enforce server-side content/size checks too. Return a short catalog search term, not a long caption. See [Vision label detection](https://docs.cloud.google.com/vision/docs/labels).
6. Inject both implementations through `SmartSearch(voice: ..., image: ...)` into the existing `Storefront(searchService: ..., store: store)` composition in `lib/main.dart`. Keep provider-specific code in separate service files. No homepage redesign is required.

The current text matcher requires **every word** in the returned query to occur in the product's name, description or tags. For an image of rice, return a matching term such as `rice`, rather than `white rice in a plastic bag on a table`. Speech in an Indian language will also need catalog translations/tags or a deliberate normalization step if the catalog itself is English-only. Vision labels are a starting point for keyword search, not an exact visual product-matching index.

## Acceptance checks after connection

- Voice: allow and deny microphone permission; test silence, cancellation, the chosen Indian languages, and a known stocked product.
- Image: upload a known product, an unrelated image, an invalid file and an oversized file; verify useful empty/error states.
- Check that provider results populate the existing typed search and open the normal product flow.
- Test signed-out and signed-in users according to the intended guest policy; verify backend limits and failures.
- Confirm there are no private provider credentials in the generated web files and no unintended audio/image retention.

Cloud setup and adapter implementation remain a separate integration step; the existing explanatory fallback messages are expected until that step is completed.
