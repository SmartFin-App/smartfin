# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Flutter client for SmartFin, a personal finance copilot for Thai users. See the root `../CLAUDE.md` for the monorepo picture and `../smartfin-backend/CLAUDE.md` for the API it talks to.

## Commands

Dart SDK ^3.11.1. Run these from `smartfin-flutter/`.

```bash
flutter pub get
flutter run                                     # Android emulator / iOS sim / macOS
flutter run --dart-define=API_BASE_URL=http://MAC_LAN_IP:3000   # physical phone
flutter build apk --dart-define=API_BASE_URL=https://…          # release against a deployed backend
flutter analyze                                 # lint — flutter_lints, no custom rules enabled
flutter test
flutter test test/widget_test.dart -n 'name'    # single test
```

The Go backend must be running on port 3000 for anything past the auth screens to work.

Adding or upgrading a package with native code (e.g. `flutter_local_notifications`) needs a full `flutter run` after `flutter pub get` — neither hot reload nor hot restart loads a new plugin, and the missing-plugin error looks like a bug in the feature.

**Launch the Android emulator with an explicit IPv4 resolver:**

```bash
~/Library/Android/sdk/emulator/emulator -avd Pixel_8_API_35 -dns-server 8.8.8.8,1.1.1.1
```

Without it, login fails with a Firebase "network error" that looks like broken auth but is not. The dev Mac's DNS is IPv6-only, the emulator cannot pass an IPv6 nameserver into the guest, and the guest boots with **no resolver at all**. API calls still work (they target the literal IP `10.0.2.2`), so only the hostname-resolving part — Firebase — fails. Launching from Android Studio's device manager never passes this flag. The durable fix is to put an IPv4 DNS server first in the Mac's network settings.

The pub package name is **`smart_fin`**, so imports are `package:smart_fin/…` — not `smartfin`, and not relative paths.

## Structure

Feature-first: `lib/features/<feature>/{data,presentation}` for auth, dashboard, transactions, scanner, coach, subscriptions, splash. Shared UI in `lib/widgets/` (see **UI kit** below), design tokens in `lib/constants/`.

**There is no BLoC or Riverpod.** All state is `StatefulWidget` + `setState`, and repositories are constructed directly at the call site. Match that pattern.

Routing is one top-level `GoRouter` in `lib/core/router/app_router.dart`; every screen is registered there with a name, and `lib/widgets/bottom_nav_bar.dart` navigates by those names.

## Traps — check these before creating or editing a file

**The router imports `presentation/*_screen.dart`.** The only view under a `views/` directory is `splash/presentation/views/splash_view.dart`. The comment-only stubs (`bloc/`, duplicate coach files, `core/injection/`, placeholder widgets, an unused Outfit theme in `lib/src/`) were deleted in Sept 2026; don't recreate them.

**Auth is intentionally bypassed.** `_authRedirect` in `app_router.dart` returns `null` unconditionally under a `// BYPASS AUTH REDIRECT FOR TESTING` comment, so the paths listed in `_protectedPaths` (`/home`, `/history`, `/coach`, `/profile`) are reachable while logged out. Restore it only when asked. While bypassed, screens send an empty user id (see below), and the backend will return empty data rather than an error.

**DI is declared but unused.** `lib/core/di/injection_container.dart` registers `FirebaseAuth` with `get_it`, and `main.dart` awaits `di.init()`, but nothing ever resolves `sl<…>()`. Repositories are constructed directly at their call sites. Follow the surrounding pattern rather than half-migrating to `get_it`.

## Backend base URL comes from `API_BASE_URL`

`lib/core/network/dio_client.dart` uses `--dart-define=API_BASE_URL=…` when given (a trailing slash is dropped). Without it, it falls back to a local backend:

| Target | URL |
| --- | --- |
| Android emulator | `http://10.0.2.2:3000` (host loopback) |
| iOS simulator / macOS | `http://localhost:3000` |

Anything running on a **real phone needs the define**: a LAN IP (`http://192.168.x.x:3000`) for local development, or the deployed backend's URL for a release build. A release built without it silently points at the emulator address and every request fails.

Dio timeouts are 10s connect / **60s receive**. The receive value must stay above the backend's own 45s coach budget — both clocks start together, so an equal value aborts requests the server has just finished. Never lower it below 45s. A single `InterceptorsWrapper` logs every request and rewraps `DioException` into `ApiException` with a human-readable message.

Repositories return `ApiResponse<T>` (`ApiResponse.success(data)` / `ApiResponse.error(msg)`) rather than throwing — callers check `.success`. Keep new data-layer methods consistent with that.

## Screens with non-obvious behaviour

- **Splash** waits on `authStateChanges().first` (5s timeout), not a fixed delay. Firebase restores the persisted session asynchronously, and a timer that expired first sent a signed-in user to the login screen. The branding pause runs concurrently with that wait — don't reintroduce a `Future.delayed` gate.
- **Coach** restores its transcript from `GET /api/coach/history/:user_id` on init, falling back to the welcome greeting only when there is none. The screen is disposed on every tab switch, and the client builds the coach's `history` payload from that list, so without the restore the agent also loses its conversational memory.
- **Transaction detail** (`/transaction/:id`) is reached with `context.push`, not `go`, so back returns to History; it returns `true` when the record changed so the list refreshes. Edit and delete both send `user_id` — the API refuses single-transaction writes without it.
- **History** filters and searches server-side (category, month, `search` on merchant) so its month window matches the summaries, and search covers every transaction rather than only the loaded ones. It **pages** 50 at a time with `skip`, loading the next page near the bottom of the list. Before paging, the list stopped silently at the 50 newest transactions. A generation counter drops pages that arrive after the filters changed. The month filter is a `‹ Sep 2026 ›` stepper, which can step back without limit but not past the current month, plus an "All months" chip. The category filter lists expense categories only. It accepts **starting filters as query parameters** — `/history?type=expense&category=Food&month=2026-09` — read in `app_router.dart` and applied in `initState` before the first load. The dashboard's top-categories rows use this and always send all three: a category alone would pull that category's transactions from every month, so History's total would stop matching the card. The bottom nav still opens History unfiltered. Because the route builder lives on the top-level `appRouter`, changes to it need a hot **restart**, not a reload.
- **Dashboard** leads with a monthly card that is a **budget donut** over a **top-categories** list, both built only from the summary the screen already loads (`total_expenses`, `budget_limit`, `expense_by_category`), so it adds no request. The donut (fl_chart `PieChart`) has one segment per category, coloured from `_categoryStyle`, and fills up to the budget limit, with the unspent budget as the grey track. Over budget, the ring is simply full and the centre shows "฿X over" in red. With no budget set, it is a plain category breakdown with a "Set a monthly budget" link to Profile. The top-3 rows below double as its legend. This replaced the old budget card, whose headline was "available to spend": `income − expenses`, where income is an *assumed* profile figure credited in full on day one, so that number was a projection presented as a balance. Don't reintroduce an income-based headline. Spent-vs-own-budget is fine because both figures are real. The cat speech bubble (a hardcoded `_coachMessage`) and the "You saved ฿X last month" pill were removed and should stay gone. Below it, an **Upcoming bills** card lists up to three active bills that are overdue or due within 7 days, and is hidden when there are none; tapping it opens the tracker.
- **Subscriptions & Bills** (`/subscriptions`, `lib/features/subscriptions/`) is reached with `context.push` from Profile and from the dashboard card, and pops `true` when anything changed. It groups bills into Overdue / Due soon / Later / Paused, with add, edit (tap a row), delete and **Mark paid**, which logs the bill as an expense for today and moves its due date on a cycle. **Never parse `next_due_date` on the client** — it is a UTC instant for a Thai calendar day, and the device clock (the emulator's is often UTC) would put it on the wrong day. Use the server's `due_date`, `days_until_due` and `status`. Two guards stop a double tap booking a bill twice: a per-bill in-flight set here, and `expected_due_date`, which makes the server answer 409 to a repeat. The edit sheet sends `next_due_date` only when the user changed it, because the server re-anchors the billing day to whatever date it receives.

## Bill reminders (local notifications)

`lib/features/subscriptions/services/bill_reminder_service.dart` schedules on-device reminders with `flutter_local_notifications` 22.x and `timezone`: 09:00 the day before a bill is due and 09:00 on the day, in **`Asia/Bangkok`** regardless of the device's zone. The backend runs no jobs, so there is no push.

- **Scheduling is a full resync.** `syncAll` cancels every pending reminder whose payload starts with `bill:` and schedules afresh; it runs after every successful bill load — the tracker screen and the dashboard — so edits, payments, pauses and deletions never leave a stale reminder. Times already past are skipped, because `zonedSchedule` throws on them.
- **Notification ids are derived from the ObjectID hex** (`idFor`), not `String.hashCode`, which is not stable between runs and would leave old reminders uncancellable.
- **Scheduling is inexact** (`inexactAllowWhileIdle`), so no exact-alarm permission is declared. `POST_NOTIFICATIONS` is requested on the tracker screen once there is an active bill — never at app start. Logout and account deletion call `cancelAll`.
- **Native setup** the plugin needs: core library desugaring in `android/app/build.gradle.kts`, and `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` plus the plugin's two receivers in `AndroidManifest.xml`.
- The bell on the tracker's header sends a test reminder now or in 10 seconds, which is how to check reminders without waiting for 09:00. `BillReminderService.enabled` is a kill switch; every method logs failures rather than throwing.

## User identity

Firebase (core/auth/firestore, google_sign_in) handles login; `lib/firebase_options.dart` is generated by FlutterFire.

The backend keys every record by **Firebase UID**, and screens read it inline at each call site as `FirebaseAuth.instance.currentUser?.uid ?? ''` — there is no central user/session object. That `?? ''` fallback is why a bypassed-auth session silently gets empty results.

## Slip capture has two paths

**Manual:** `/scanner` (camera) → `/processing` → `/verify`. `ScannerRepositoryImpl` posts the image as multipart `FormData` to `/api/scanner/process`; the backend extracts fields with Gemini Vision but persists nothing, so the **verify screen is what actually creates the transaction**. Never skip it.

**Automatic:** `lib/features/scanner/services/gallery_watcher_service.dart` — a singleton watching the photo library via `photo_manager` for new Thai banking e-slips.

**A hand-picked selection wins over the cascade.** `selectedAlbumIds()` holds album ids chosen in Profile → Slip Folders (`smartfin_slip_album_ids`, empty = automatic), and `findSlipAlbums()` uses exactly those when any still exist. No hardcoded list covers every bank, renamed folder, or the people who screenshot slips instead of saving them. Otherwise it auto-matches by name, our own album first:

1. `"SmartFin Receipts"`
2. Keywords: `smartfin`, `receipt`, `slip`, `สลิป`, `ใบเสร็จ`
3. `bankAlbumAliases` — `kplus`, `kasikorn`, `scbeasy`, `krungthai`, `bualuang`, `krungsri`, `kma`, `ttb`, `promptpay`, `truemoney`, `mymo` and more

**Compare album names only through `normalizeAlbumName`**, which lower-cases and strips everything but letters, digits and combining marks. Real phones spell the same folder "KPLUS", "K PLUS" and "K-Plus", and the old matcher looked for the literal `'k plus'`, so the folder most users actually have never matched. Marks are kept because Thai vowel signs are marks, not letters — dropping them turns `สลิป` into `สลป`. `test/gallery_watcher_album_match_test.dart` covers both.

`findSlipAlbums()` returns **every** match, capped at `_maxWatchedAlbums` (8), and `checkForNewSlipsDetailed()` offers the newest unprocessed asset across all of them — someone with two banking apps had slips from one of them permanently hidden when this stopped at the first album.

**Screenshots is deliberately not auto-matched** (nor Download / Recent / All): matching those made every photo in the camera roll look like a payment slip. Someone who screenshots slips can tick that folder in the picker. No match returns `SlipCheckStatus.noAlbum`, and `checkForNewSlipsDetailed()` distinguishes that from `permissionDenied`, `disabled`, and `none` so the UI can say which.

**The user-facing name for this feature is "Auto-Detect"** — in the action hub, the profile toggle, and the slide deck. `GalleryWatcherService` keeps its name in code because it accurately describes the mechanism; don't surface "gallery watcher" in UI copy. The feature also needs a real MediaStore album to exist: `photo_manager` lists albums from MediaStore, not the filesystem, so an empty `/sdcard/Pictures/SmartFin Receipts` directory is **not** an album and correctly reports `noAlbum`.

Processed assets are deduped by id in `SharedPreferences` under `smartfin_processed_slip_ids` (capped at 300, global rather than per-user), and the watcher is user-toggleable via `smartfin_gallery_watcher_enabled` (default on). Detections surface through `scanner/presentation/widgets/slip_detection_sheet.dart`.

A gallery slip is marked processed **only after its transaction saves**, not when the scan starts: its asset id rides through the flow as `{'file', 'assetId'}` on the `/processing` extra and `asset_id` on the `/verify` extra. Marking it earlier meant a failed scan hid the receipt from the watcher permanently. Photo-library permission is requested through `PhotoManager.requestPermissionExtend()`; the Android and iOS permission entries are already in the native projects.

## Conventions

**Scroll views use `ClampingScrollPhysics`, not `BouncingScrollPhysics`.** The app targets Android, whose native edges stop dead rather than rubber-banding; bouncing let every screen be dragged into empty space past its last item. Where a `RefreshIndicator` is attached (dashboard, history), keep the parent: `ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics())` — that parent is what lets a short list still accept a pull-to-refresh drag.

**SmartFin tracks spending only — there is no income and no savings goal.** Setup asks for an optional monthly **budget** instead (it used to be set silently to 70% of an income figure); Profile edits the budget; the dashboard has no savings-goal card and no income prompt; the action hub, manual-add and History have no income option or filter. The backend refuses income transactions and returns expenses only, so an income row from before the change never appears. Don't reintroduce an income field, an income-based figure ("available", "saved", "left to save") or a savings goal. The income keys still listed in Profile's logout cleanup are there to clear old installs.


Money is **integer Thai Baht (฿)** end-to-end — the API sends `int64` and preformatted `formatted_amount` / `formatted_date` strings; don't reintroduce decimals or client-side float math. Copy is warm in tone everywhere, but the 🐾 paw and cat imagery appear **only on the coach screen** (greeting, error replies, `lucky_cat.png` avatar). Toasts, empty states, bill reminders and sheet titles elsewhere must not use them.

**Tab screens share one header title**: `PageTitleRow` (`lib/widgets/page_title_row.dart`) on History, AI Coach and Profile. It shows a left-aligned 24px Bricolage title in a 40px row, 48px from the top, with an optional action on the right (History's filter). There is no back button, because the bottom nav already does that job. Use it for any new tab screen rather than hand-building a title row. Size the pinned `SliverAppBar` around it with `PageTitleRow.barHeight(context, contentBottom)`, where `contentBottom` is where the header's content ends, measured from the top of the screen (96 for a title alone, 156 with History's search field). The app bar adds the status-bar inset on top of any fixed height, which left about 60pt of empty space under the title on iPhones.

**The add button sits inside the bottom nav bar**, as the middle of five slots, on every tab (`lib/widgets/bottom_nav_bar.dart`). It used to float 24px above the bar, where it covered the coach's chat input. Coach and Profile hid it with a `showFab` flag, which left an empty gap in the bar. It is a filled orange square with no label, not a tab, because it opens the action hub rather than a page. Don't make it float again.

**Category colours are one palette, copied into six screens**: dashboard, history (`transaction_list_screen`), transaction detail, manual add, verify and subscriptions. Food `FF9F29` orange, Transport `2563EB` blue, Bills `0D9488` teal, Groceries `65A30D` green, Entertainment `7C3AED` violet, Shopping `DB2777` pink, Health `DC2626` red, Other `9E9E9E` grey. They were chosen so neighbouring slices of the dashboard donut stay distinguishable. Bills used to be `FF9800`, almost the same as Food's orange. Change a colour in all six files at once, and don't give two categories the same hue.

**The only chart is the dashboard's budget donut** (`fl_chart`, inline in `dashboard_screen.dart`). Tests are few: the album matcher, `CoachAction` parsing, a login-screen smoke test, and layout tests for the action hub and both slip sheets (rendered with the real theme, failing on any overflow). The whole app can't be pumped in a widget test, because the splash needs Firebase initialised.

## UI kit (refined warm)

New and converted screens build from `package:smart_fin/widgets/ui/ui.dart`, which also exports the tokens:

- **Tokens** (`lib/constants/`): `AppColors` (cream background, white cards, `surfaceMuted` for tracks and skeletons, `primary` orange for fills, `primaryText` darker orange for text and links, since the brand orange is about 2:1 on white; `onPrimary` (the ink) for text and icons **on** an orange fill — filled buttons, the nav's + button, the coach's send button — because white on the orange is also about 2:1; `textDark` / `textSecondary` / `textMuted`; `danger`, `success`), `AppRadius` (sm 10, md 14, lg 20, xl 28, pill), `AppSpacing` (4px grid, `screen` = 20 side inset), `AppShadows.card`, and `AppTextStyles` (Bricolage `display` / `title` / `heading`, Inter `body` / `bodyStrong` / `caption` / `label` / `button`, `amount` with tabular figures).
- **Theme** (`lib/constants/app_theme.dart`, wired in `main.dart`): stock `FilledButton`, `OutlinedButton`, `TextButton`, inputs, cards, sheets, dialogs, floating snackbars and switches are already styled. Prefer them to hand-built `GestureDetector` + `Container` buttons. The sheet theme deliberately sets no drag handle, because several sheets draw their own.
- **Components**: `AppCard` (tappable with ripple; `flat` drops the shadow), `AppChip` (selectable pill), `AppIconButton` (40px header action with an optional count badge; `filled` for a screen's main action, such as add), `SectionHeader` (title + "See all"), `IconTile` (tinted icon square), `ListRow` + `ListRow.divider()`, `AppButton` (`.secondary`, `.text`; `loading` blocks a second tap), `Skeleton` (pulsing placeholder), `StatusMessage` (empty and failed states, plain copy), `showAppToast(context, message, error:)` (floating confirmation; red for errors), `SubpageHeader` (blurred back-button + centred-title header for pushed screens; start content at `SubpageHeader.contentTop`), `CategoryTile` (one choice in the 2-column category picker on manual add and verify). Use the toast rather than hand-building green/red `SnackBar`s.
- **Pinned bars need `Stack(fit: StackFit.expand)`** when the scrolling child is a `SingleChildScrollView`: inside a plain `Stack` it shrinks to its content, so a short form's save bar (or the nav) sat mid-screen. `CustomScrollView` and `ListView` always fill, so the tab screens built on them don't need it.
- **Copy style**: sentence case, at least 12px. No letter-spaced capitals (`'TOP CATEGORIES'`); they were retired from every screen.
- **The camera screen stays dark** (it is a viewfinder). Its controls use a dark translucent backing, not frosted white, because a white slip fills most of the frame.

**Every screen and sheet now builds from the kit.** The only literal colours left outside `lib/constants/` are the category palette (see above), the Auto-Detect blue in the action hub, and a few overlay tints (the camera's scan line and frame, Profile's photo-upload scrim); don't add new ones. Manual add takes whole baht only (digits keyboard), since money is integer ฿. On the coach screen, user bubbles are a soft orange tint with dark text, because white on the brand orange is about 2:1 and hard to read. Coach replies render the Markdown the model writes (`**bold**` and `*`/`-` bullets) in `_buildRichText`; everything else shows as written. 
