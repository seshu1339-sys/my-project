---
name: fix-queue
description: Process the LocaMarket admin AI Agent's fix queue (fixRequests in Firestore) on this PC - write and test fixes the admin asked for, deploy only fixes the admin approved with OK, and undo on request. Use when the owner runs /fix-queue or a /loop of it.
---

# Fix queue

Follow `tools/fix-queue/README.md` exactly. In short:

1. `node tools/fix-queue/fixq.mjs list`. If nothing is listed, say "Fix queue empty" in one line and stop.
2. **requested**: `claim`, `show`. Work on a branch `fix/<id>` from `main`: find the cause from the problem's cases (screen, option,
   message, phone models), write the smallest fix plus a test, run `flutter analyze`, `flutter test` and the functions tests with the
   emulators. Commit on the branch, write the diff to a temp file, then `ready <id> --kind … --summary … --tests … --diff … --branch …`.
   Do NOT deploy. If the tests cannot pass, `failed <id> --note "<simple words>"`.
3. **approved** (the admin pressed OK in the panel): `deploying`, merge into `main` (the commit before is the backup), deploy ONLY what
   the fix changed (functions by name, the hosting target, settings for design, Closed testing for app code), check it works, then
   `live <id> --commit <sha> --how "<what>"`. If anything breaks, put the backup back and `failed`.
4. **undoRequested**: revert the fix's merge on `main`, deploy the same way, check, `undone <id> --commit <sha>`.

Never deploy, upload or change settings for a request that is not approved. Never add anything that costs money. Report each request in
one line at the end (id, title, what happened).
