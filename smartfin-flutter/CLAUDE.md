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
- **History** filters server-side (type, category, month) so its month window matches the summaries; only the free-text search is local.

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

Money is **integer Thai Baht (฿)** end-to-end — the API sends `int64` and preformatted `formatted_amount` / `formatted_date` strings; don't reintroduce decimals or client-side float math. Coach and dashboard copy uses a warm tone with a 🐾 paw emoji.

Charts are `fl_chart` (`dashboard/presentation/chart_widgets.dart`). Test coverage is essentially absent — `test/` holds only the default `widget_test.dart`.
