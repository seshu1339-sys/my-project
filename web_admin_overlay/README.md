# Admin / Master Agent PWA overlay

Files here are copied on top of a plain copy of `build/web` by
`scripts/build-admin-web.ps1`, producing `build/admin_web` — the directory
the `admin` Firebase Hosting target serves. This gives the admin panel ("Add
to Home Screen" on iPhone) its own name/icon, distinct from the customer
app's, without a second Flutter compile: the compiled Dart/JS app (and its
hidden-route OTP gate) is byte-identical either way, only this static HTML/
manifest/icon metadata differs.

**`icons/*.png` and `favicon.png` are placeholders** — direct copies of the
customer app's icons, just so the overlay mechanism is complete and testable
end-to-end today. Replace them with real "Locamarket Control" artwork at the
same filenames/sizes before relying on the distinct icon showing up on a
real iPhone's Home Screen. `index.html`/`manifest.json`'s name strings are
already final ("Locamarket Control").
