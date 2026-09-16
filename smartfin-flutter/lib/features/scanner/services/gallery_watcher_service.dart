import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Representation of a newly detected payment slip from the gallery
class DetectedSlip {
  final AssetEntity asset;
  final File file;
  final String albumName;
  final DateTime createDateTime;

  const DetectedSlip({
    required this.asset,
    required this.file,
    required this.albumName,
    required this.createDateTime,
  });
}

/// Why a slip check came back without a slip — so the UI can tell "you denied photo
/// access" apart from "there is nothing new", which used to look identical.
enum SlipCheckStatus { found, none, noAlbum, permissionDenied, disabled }

class SlipCheckResult {
  final SlipCheckStatus status;
  final DetectedSlip? slip;

  const SlipCheckResult(this.status, [this.slip]);
}

/// One album on the device, as offered in the folder picker.
class GalleryAlbum {
  final String id;
  final String name;
  final int count;

  /// Whether the automatic cascade would pick this album on its own — the
  /// picker shows it as a suggestion so the user knows what is already watched.
  final bool autoMatched;

  const GalleryAlbum({
    required this.id,
    required this.name,
    required this.count,
    required this.autoMatched,
  });
}

/// Service that monitors the "SmartFin Receipts" gallery album
/// to detect newly saved PromptPay / mobile banking payment confirmation slips.
class GalleryWatcherService {
  static final GalleryWatcherService _instance = GalleryWatcherService._internal();
  factory GalleryWatcherService() => _instance;
  GalleryWatcherService._internal();

  static const String _processedSlipsKey = 'smartfin_processed_slip_ids';
  static const String _watcherEnabledKey = 'smartfin_gallery_watcher_enabled';
  static const String _selectedAlbumsKey = 'smartfin_slip_album_ids';
  static const String _folderPromptSeenKey = 'smartfin_slip_folder_prompt_seen';
  static const String targetAlbumName = 'SmartFin Receipts';

  /// Ceiling on albums read per check. The watcher runs on every dashboard load,
  /// and each album costs a MediaStore query.
  static const int _maxWatchedAlbums = 8;

  /// Folder names Thai banking apps save slips into, written without spaces or
  /// punctuation because that is how [normalizeAlbumName] compares them: real
  /// phones show "KPLUS", "K PLUS" and "K+ Plus" for the same app, and matching
  /// the literal string 'k plus' missed every one of them but the middle.
  static const List<String> bankAlbumAliases = [
    'kplus', 'kasikorn', 'kbank',
    'scbeasy', 'scb',
    'krungthai', 'ktb', 'next',
    'bualuang', 'bangkokbank', 'bbl',
    'krungsri', 'kma',
    'ttb', 'tmb',
    'promptpay', 'truemoney', 'truewallet',
    'mymo', 'gsb',
    'uob', 'cimb', 'lhbank', 'baac',
  ];

  /// Keywords that mark a folder as slip-specific whatever the bank.
  static const List<String> slipKeywordAliases = [
    'smartfin', 'receipt', 'slip', 'สลิป', 'ใบเสร็จ',
  ];

  /// Lower-cases and drops everything that is not a letter, digit or combining
  /// mark, so "K PLUS", "KPLUS" and "k-plus" all compare equal.
  ///
  /// Marks are kept because Thai vowel and tone signs are marks rather than
  /// letters: dropping them turned "สลิป" into "สลป" and would collide words
  /// that differ only by a vowel. The backend's slip scorer keeps them too.
  static String normalizeAlbumName(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true), '');

  /// Check if the watcher is enabled by the user
  Future<bool> isWatcherEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_watcherEnabledKey) ?? true;
  }

  /// Enable or disable the watcher
  Future<void> setWatcherEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_watcherEnabledKey, enabled);
  }

  /// Request photo permissions
  Future<bool> requestPermission() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      return ps.isAuth || ps.hasAccess;
    } catch (e) {
      debugPrint('Error requesting photo permission: $e');
      return false;
    }
  }

  /// Check if photo permissions have already been granted
  Future<bool> hasPermission() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      return ps.isAuth || ps.hasAccess;
    } catch (e) {
      return false;
    }
  }

  /// Album ids the user picked by hand in Profile → Auto-Detect Slips.
  ///
  /// Empty means "decide automatically"; a non-empty set replaces the cascade
  /// entirely, which is how a bank we have never heard of, a renamed folder or
  /// Screenshots gets watched.
  Future<Set<String>> selectedAlbumIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_selectedAlbumsKey) ?? const <String>[]).toSet();
  }

  Future<void> setSelectedAlbumIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(_selectedAlbumsKey);
    } else {
      await prefs.setStringList(_selectedAlbumsKey, ids.toList());
    }
  }

  /// Whether the passive dashboard check may offer the folder picker.
  ///
  /// True only once: a background check that nags on every app resume is worse
  /// than a feature that stays quiet. Tapping Auto-Detect asks for a scan
  /// explicitly, so that path offers the picker every time regardless.
  Future<bool> shouldOfferFolderPicker() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_folderPromptSeenKey) ?? false);
  }

  Future<void> markFolderPickerOffered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_folderPromptSeenKey, true);
  }

  /// True when an album looks slip-specific on name alone.
  ///
  /// Screenshots is deliberately not here: most people's screenshot folder is
  /// mostly not slips, and auto-offering all of it was the "lunch photo"
  /// problem. The user can still select it by hand in the picker.
  static bool looksLikeSlipAlbum(String albumName) {
    final norm = normalizeAlbumName(albumName);
    if (norm.isEmpty) return false;
    if (norm == normalizeAlbumName(targetAlbumName)) return true;
    for (final keyword in slipKeywordAliases) {
      if (norm.contains(normalizeAlbumName(keyword))) return true;
    }
    for (final alias in bankAlbumAliases) {
      if (norm.contains(alias)) return true;
    }
    return false;
  }

  /// Every album worth watching, best first.
  ///
  /// Returns all matches rather than the first: people commonly have more than
  /// one banking app, and stopping at the first match meant slips saved by the
  /// others were never offered.
  Future<List<AssetPathEntity>> findSlipAlbums() async {
    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );

      debugPrint(
          "GalleryWatcher: Available albums in gallery (${albums.length}): ${albums.map((a) => a.name).toList()}");

      final chosen = await selectedAlbumIds();
      if (chosen.isNotEmpty) {
        final picked = albums.where((a) => chosen.contains(a.id)).toList();
        debugPrint(
            "GalleryWatcher: Using ${picked.length} user-selected album(s): ${picked.map((a) => a.name).toList()}");
        // Every selected album is gone (uninstalled app, cleared folder): fall
        // through to the cascade rather than silently watching nothing.
        if (picked.isNotEmpty) return picked;
      }

      // The SmartFin album first when it exists, then anything else that reads
      // as a slip folder, so our own album still wins when both are present.
      final normalizedTarget = normalizeAlbumName(targetAlbumName);
      final matches = albums.where((a) => looksLikeSlipAlbum(a.name)).toList()
        ..sort((a, b) {
          final aIsTarget = normalizeAlbumName(a.name) == normalizedTarget;
          final bIsTarget = normalizeAlbumName(b.name) == normalizedTarget;
          if (aIsTarget != bIsTarget) return aIsTarget ? -1 : 1;
          return 0;
        });

      // Deliberately no fallback to Download / Recent / All: matching those made
      // every photo in the camera roll look like a payment slip, and auto-offered
      // lunch photos to the scanner.
      if (matches.isEmpty) {
        debugPrint("GalleryWatcher: No slip-specific album found.");
      } else {
        debugPrint(
            "GalleryWatcher: Matched ${matches.length} album(s): ${matches.map((a) => a.name).toList()}");
      }
      return matches;
    } catch (e) {
      debugPrint('Error finding slips album: $e');
      return const [];
    }
  }

  /// The single best album, for callers that only need one.
  Future<AssetPathEntity?> findSlipsAlbum() async {
    final albums = await findSlipAlbums();
    return albums.isEmpty ? null : albums.first;
  }

  /// Every image album on the device, for the folder picker in Profile.
  ///
  /// Sorted with the auto-matched ones first so the suggestions are visible
  /// without scrolling past the camera roll.
  Future<List<GalleryAlbum>> listAlbums() async {
    try {
      final permitted = await requestPermission();
      if (!permitted) return const [];

      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      final result = <GalleryAlbum>[];
      for (final album in albums) {
        result.add(GalleryAlbum(
          id: album.id,
          name: album.name,
          count: await album.assetCountAsync,
          autoMatched: looksLikeSlipAlbum(album.name),
        ));
      }
      result.sort((a, b) {
        if (a.autoMatched != b.autoMatched) return a.autoMatched ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return result;
    } catch (e) {
      debugPrint('Error listing albums: $e');
      return const [];
    }
  }

  /// Check for new unprocessed slips, reporting *why* when there are none.
  Future<DetectedSlip?> checkForNewSlips() async =>
      (await checkForNewSlipsDetailed()).slip;

  /// Check if there are any new unprocessed slips in the album
  Future<SlipCheckResult> checkForNewSlipsDetailed() async {
    try {
      final enabled = await isWatcherEnabled();
      if (!enabled) return const SlipCheckResult(SlipCheckStatus.disabled);

      final permitted = await requestPermission();
      if (!permitted) {
        return const SlipCheckResult(SlipCheckStatus.permissionDenied);
      }

      final albums = await findSlipAlbums();
      if (albums.isEmpty) {
        debugPrint("GalleryWatcher: No watched album found in gallery yet.");
        return const SlipCheckResult(SlipCheckStatus.noAlbum);
      }

      final prefs = await SharedPreferences.getInstance();
      final processedIds = (prefs.getStringList(_processedSlipsKey) ?? []).toSet();

      // Newest unprocessed slip across every watched album, not merely the first
      // album's: with two banking apps installed, whichever album happened to
      // sort first would otherwise hide the slip just saved by the other.
      AssetEntity? newest;
      AssetPathEntity? newestAlbum;
      for (final album in albums.take(_maxWatchedAlbums)) {
        final assets = await album.getAssetListRange(start: 0, end: 10);
        for (final asset in assets) {
          if (processedIds.contains(asset.id)) continue;
          if (newest == null || asset.createDateTime.isAfter(newest.createDateTime)) {
            newest = asset;
            newestAlbum = album;
          }
          // Assets come back newest-first, so the rest of this album is older
          // than the one just considered.
          break;
        }
      }

      if (newest != null) {
        final File? file = await newest.file;
        if (file != null && await file.exists()) {
          return SlipCheckResult(
            SlipCheckStatus.found,
            DetectedSlip(
              asset: newest,
              file: file,
              albumName: newestAlbum?.name ?? '',
              createDateTime: newest.createDateTime,
            ),
          );
        }
      }

      return const SlipCheckResult(SlipCheckStatus.none);
    } catch (e) {
      debugPrint('Error checking for new slips: $e');
      return const SlipCheckResult(SlipCheckStatus.none);
    }
  }

  /// Mark a slip asset ID as processed so it won't prompt the user again
  Future<void> markSlipAsProcessed(String assetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final processedIds = (prefs.getStringList(_processedSlipsKey) ?? []).toSet();
      processedIds.add(assetId);

      // Keep set size reasonable (last 300 IDs)
      final list = processedIds.toList();
      if (list.length > 300) {
        list.removeRange(0, list.length - 300);
      }

      await prefs.setStringList(_processedSlipsKey, list);
      debugPrint('GalleryWatcher: Marked slip $assetId as processed.');
    } catch (e) {
      debugPrint('Error marking slip as processed: $e');
    }
  }

  /// Fetch all slips from the album for manual selection
  Future<List<AssetEntity>> getAllSlips({int limit = 30}) async {
    try {
      final permitted = await requestPermission();
      if (!permitted) return [];

      final album = await findSlipsAlbum();
      if (album == null) return [];

      return await album.getAssetListRange(start: 0, end: limit);
    } catch (e) {
      debugPrint('Error getting all slips: $e');
      return [];
    }
  }
}
