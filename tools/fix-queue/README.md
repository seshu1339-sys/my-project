# Fix queue: the admin AI Agent's fixes, done by Claude Code on this PC

The admin panel's **AI Agent: problems & fixes** page (`lib/ui/fix_agent_page.dart`) lists every app problem with the most affected
people first. When the admin presses **Fix**, a fix request waits in Firestore (`fixRequests`). Claude Code on this PC picks it up,
writes the fix, runs the tests and shows the exact changes in the panel. **Nothing goes live until the admin presses OK.**

Start it in Claude Code on this PC (it keeps checking while this PC and the session are on):

```
/loop 15m /fix-queue
```

Or once: `/fix-queue`. The panel shows "Fix agent on the PC is running" when it checked in the last 45 minutes.

## What Claude Code does each time (the `/fix-queue` skill follows this)

1. `node tools/fix-queue/fixq.mjs list`. Nothing listed: stop.
2. For each **requested** request:
   1. `fixq.mjs claim <id>`, then `fixq.mjs show <id>`: the problem, its cases (screen, option, phone models, versions), the admin's
      instruction (if any: follow it exactly).
   2. Make a branch `fix/<id>` from `main`. Find the cause in the code, write the smallest fix and a test for it.
   3. Run the tests: `flutter analyze` and `flutter test` (app and website), and the functions tests with the emulators
      (`firebase.cmd emulators:exec --only firestore,auth,storage --project demo-neighbourly "npm test"` in `functions/`). If they fail, fix
      them or report `fixq.mjs failed <id> --note "<why, in simple words>"`.
   4. Commit on the branch. `git diff main...fix/<id> > %TEMP%\fix-<id>.diff`.
   5. `fixq.mjs ready <id> --kind <website|admin|server|design|app> --summary "<one plain sentence>" --tests "<n passed>" --diff <file> --branch fix/<id>`.
      Stop there. Do not deploy.
3. For each **approved** request (the admin pressed OK):
   1. `fixq.mjs deploying <id>`. Merge `fix/<id>` into `main`; the commit before the merge is the backup.
   2. Deploy only what the fix changed:
      - **server**: `firebase deploy --only "$(node scripts/changed-functions.cjs <last deployed commit>)"` (and `firestore:rules` /
        `storage` when rules changed), then `node scripts/clean-function-images.cjs` (Artifact Registry stays under its free 0.5 GB).
      - **website / admin**: build (`--dart-define-from-file=firebase-config-web.json`), the shop site ALONE and last (it must have
        about 529 files; building other targets in the same run has left it incomplete), `scripts/build-admin-web.ps1` for the admin site,
        `firebase deploy --only hosting:<target>`; locamarket.in with the Hostinger deploy (same build zip).
      - **design / remote config**: write the settings value (with a `designHistory` line for Undo). The apps take it at once.
      - **app**: raise the version in `pubspec.yaml`, build the 3 signed bundles, upload to the Closed testing track with
        `node tools/play-upload/upload.mjs <flavor> --track <closed track> --yes`. Google reviews the build before people get it.
   3. Check it works (the page loads, the function answers, the tests pass on main).
   4. `fixq.mjs live <id> --commit <merge sha> --how "<what went live>"`. The problem's reports become Solved and each person is told
      "Your problem is solved" in their language.
   5. If it breaks: put the backup back at once, then `fixq.mjs failed <id> --note "<what happened>"`.
4. For each **undoRequested** request: `git revert` the fix's merge commit on `main`, deploy the same way, check, then
   `fixq.mjs undone <id> --commit <revert sha>`.

## Rules

- Never deploy, upload or change settings for a request that is not **approved** (the panel's OK).
- Stay inside Google Cloud's free limits; never add a Google service or anything that costs money (ask the owner first).
- Never put keys or passwords in the code or the diff.
- Every step is logged in `agentLog` by `fixq.mjs`; the admin panel shows who approved, when and what changed.
- AI cost: the fix is written by Claude Code under the owner's Claude plan (not the Anthropic API key); `ready` records that as the cost.
