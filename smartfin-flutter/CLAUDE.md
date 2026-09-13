# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Flutter client for SmartFin, a personal finance copilot for Thai users. See the root `../CLAUDE.md` for the monorepo picture and `../smartfin-backend/CLAUDE.md` for the API it talks to.

## Commands

Dart SDK ^3.11.1. Run these from `smartfin-flutter/`.

```bash
flutter pub get
flutter run                                     # iOS sim / macOS / physical Android device
flutter run --dart-define=IS_EMULATOR=true      # Android emulator (see base-URL note below)
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

Feature-first: `lib/features/<feature>/{data,bloc,presentation}` for auth, dashboard, transactions, scanner, coach, onboarding, splash. Shared UI in `lib/widgets/`, theme tokens in `lib/constants/{color_style,text_style}.dart` (cream background, Bricolage Grotesque via google_fonts, wired up in `main.dart`).

**There is no BLoC, despite the layout.** Every file under `features/*/bloc/` is a ~100-byte comment stub, and `flutter_bloc` is never imported anywhere in `lib/` — both it and `flutter_riverpod` are dead weight in `pubspec.yaml`. All state is `StatefulWidget` + `setState`, and repositories are constructed directly at the call site. Match that pattern rather than half-introducing BLoC for one feature.

Routing is one top-level `GoRouter` in `lib/core/router/app_router.dart`; every screen is registered there with a name, and `lib/widgets/bottom_nav_bar.dart` navigates by those names.

## Traps — check these before creating or editing a file

**Dead scaffolding.** Several files are one-line comment stubs, not implementations:

- `lib/features/coach/{coach_screen,coach_service,chat_bubble,suggestion_chip}.dart` (~100 bytes each)
- `lib/core/injection/injection_container.dart` — the real one is `lib/core/di/injection_container.dart`
- `presentation/views/*_view.dart` for dashboard, coach, and onboarding
- every `features/*/bloc/*_{bloc,event,state}.dart` file (12 of them)

**The router imports `presentation/*_screen.dart` — those are the live files.** The only real view under a `views/` directory is `splash/presentation/views/splash_view.dart`.

**Auth is intentionally bypassed.** `_authRedirect` in `app_router.dart` returns `null` unconditionally under a `// BYPASS AUTH REDIRECT FOR TESTING` comment, so the paths listed in `_protectedPaths` (`/home`, `/history`, `/coach`, `/profile`) are reachable while logged out. Restore it only when asked. While bypassed, screens send an empty user id (see below), and the backend will return empty data rather than an error.

**DI is declared but unused.** `lib/core/di/injection_container.dart` registers `FirebaseAuth` with `get_it`, and `main.dart` awaits `di.init()`, but nothing ever resolves `sl<…>()`. Repositories are constructed directly at their call sites. Follow the surrounding pattern rather than half-migrating to `get_it`.

## Backend base URL is hardcoded per platform

`lib/core/network/dio_client.dart` picks the URL at runtime:

| Target | URL |
| --- | --- |
| Android emulator | `http://10.0.2.2:3000` (host loopback) |
| Physical Android device | `http://192.168.1.118:3000` — **hardcoded LAN IP**, goes stale when the host Mac's address changes |
| iOS simulator / macOS | `http://localhost:3000` |

`IS_EMULATOR` defaults to **`true`** on Android, so physical-device runs need `--dart-define=IS_EMULATOR=false`.

Dio timeouts are 10s connect / **60s receive**. The receive value must stay above the backend's own 45s coach budget — both clocks start together, so an equal value aborts requests the server has just finished. Never lower it below 45s. A single `InterceptorsWrapper` logs every request and rewraps `DioException` into `ApiException` with a human-readable message.

Repositories return `ApiResponse<T>` (`ApiResponse.success(data)` / `ApiResponse.error(msg)`) rather than throwing — callers check `.success`. Keep new data-layer methods consistent with that.

## Screens with non-obvious behaviour

- **Splash** waits on `authStateChanges().first` (5s timeout), not a fixed delay. Firebase restores the persisted session asynchronously, and a timer that expired first sent a signed-in user to onboarding. The branding pause runs concurrently with that wait — don't reintroduce a `Future.delayed` gate.
- **Coach** restores its transcript from `GET /api/coach/history/:user_id` on init, falling back to the welcome greeting only when there is none. The screen is disposed on every tab switch, and the client builds the coach's `history` payload from that list, so without the restore the agent also loses its conversational memory.
- **Transaction detail** (`/transaction/:id`) is reached with `context.push`, not `go`, so back returns to History; it returns `true` when the record changed so the list refreshes. Edit and delete both send `user_id` — the API refuses single-transaction writes without it.
- **History** filters server-side (type, category, month) so its month window matches the summaries; only the free-text search is local. It accepts **starting filters as query parameters** — `/history?type=expense&category=Food&month=2026-09` — read in `app_router.dart` and applied in `initState` before the first load. The dashboard's top-categories rows use this and always send all three: a category alone would pull that category's transactions from every month, so History's total would stop matching the card. The bottom nav still opens History unfiltered. Because the route builder lives on the top-level `appRouter`, changes to it need a hot **restart**, not a reload.
- **Dashboard** leads with a monthly **top-categories** card — the top 3 of `expense_by_category`, already sorted largest-first server-side — built only from the summary the screen already loads, so it adds no request. It replaced the old budget card, whose headline was "available to spend": `income − expenses`, where income is an *assumed* profile figure credited in full on day one, so that number was a projection presented as a balance. Don't reintroduce an income-based headline. The cat speech bubble that sat below it (a hardcoded, budget-percentage-driven `_coachMessage`, plus the "You saved ฿X last month" pill) was also removed, so **budget usage is no longer shown on the dashboard** — it lives only in Profile. The backend still computes `savings_message`; nothing on the client reads it. The savings-goal card adds a one-line plan from the server's projection fields — months to goal, or on track / needs ฿X per month by the target date. The client only chooses the wording; it never computes those figures. Below it, an **Upcoming bills** card lists up to three active bills that are overdue or due within 7 days, and is hidden when there are none; tapping it opens the tracker.
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

**Automatic:** `lib/features/scanner/services/gallery_watcher_service.dart` — a singleton watching the photo library via `photo_manager` for new Thai banking e-slips. It resolves a target album by cascade:

1. Exact/normalized match on `"SmartFin Receipts"`
2. Keywords: `smartfin`, `receipt`, `slip`, `สลิป`
3. Thai banking app folders: K PLUS, SCB, Krungthai, PromptPay, BBL

There is deliberately **no** fallback to Download / Recent / All — matching those made every photo in the camera roll look like a payment slip. No match returns `SlipCheckStatus.noAlbum`, and `checkForNewSlipsDetailed()` distinguishes that from `permissionDenied`, `disabled`, and `none` so the UI can say which.

**The user-facing name for this feature is "Auto-Detect"** — in the action hub, the profile toggle, and the slide deck. `GalleryWatcherService` keeps its name in code because it accurately describes the mechanism; don't surface "gallery watcher" in UI copy. The feature also needs a real MediaStore album to exist: `photo_manager` lists albums from MediaStore, not the filesystem, so an empty `/sdcard/Pictures/SmartFin Receipts` directory is **not** an album and correctly reports `noAlbum`.

Processed assets are deduped by id in `SharedPreferences` under `smartfin_processed_slip_ids` (capped at 300, global rather than per-user), and the watcher is user-toggleable via `smartfin_gallery_watcher_enabled` (default on). Detections surface through `scanner/presentation/widgets/slip_detection_sheet.dart`.

A gallery slip is marked processed **only after its transaction saves**, not when the scan starts: its asset id rides through the flow as `{'file', 'assetId'}` on the `/processing` extra and `asset_id` on the `/verify` extra. Marking it earlier meant a failed scan hid the receipt from the watcher permanently. Photo-library permission is requested through `PhotoManager.requestPermissionExtend()`; the Android and iOS permission entries are already in the native projects.

## Conventions

**Scroll views use `ClampingScrollPhysics`, not `BouncingScrollPhysics`.** The app targets Android, whose native edges stop dead rather than rubber-banding; bouncing let every screen be dragged into empty space past its last item. Where a `RefreshIndicator` is attached (dashboard, history), keep the parent: `ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics())` — that parent is what lets a short list still accept a pull-to-refresh drag.

**Hand-entered income is labelled "Extra income"** — the manual-add toggle, History's filter chip and the transaction detail row. Monthly salary is already counted from the profile's `monthly_income`, so logging it as a transaction would count it twice; manual-add shows a hint saying so when the income side is selected. This is a labelling safeguard only: the stored `type` is still `income`, and the `Salary` category still exists because renaming it would change stored category values. The Profile budget sheet also shows, live as the user types, what the budget leaves to save each month (income − budget) — the same figure the savings-goal plan is built on.

Money is **integer Thai Baht (฿)** end-to-end — the API sends `int64` and preformatted `formatted_amount` / `formatted_date` strings; don't reintroduce decimals or client-side float math. Coach and dashboard copy uses a warm tone with a 🐾 paw emoji.

**There are no charts in the app.** `fl_chart` is listed in `pubspec.yaml` but imported nowhere, and `dashboard/presentation/chart_widgets.dart` is a one-line comment stub. Test coverage is essentially absent — `test/` holds only the default `widget_test.dart`.
