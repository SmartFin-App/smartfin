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

/// Service that monitors the "SmartFin Receipts" gallery album
/// to detect newly saved PromptPay / mobile banking payment confirmation slips.
class GalleryWatcherService {
  static final GalleryWatcherService _instance = GalleryWatcherService._internal();
  factory GalleryWatcherService() => _instance;
  GalleryWatcherService._internal();

  static const String _processedSlipsKey = 'smartfin_processed_slip_ids';
  static const String _watcherEnabledKey = 'smartfin_gallery_watcher_enabled';
  static const String targetAlbumName = 'SmartFin Receipts';

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

  /// Find the "SmartFin Receipts" album, or common fallback slip albums
  Future<AssetPathEntity?> findSlipsAlbum() async {
    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );

      debugPrint("GalleryWatcher: Available albums in gallery (${albums.length}): ${albums.map((a) => a.name).toList()}");

      // 1. Exact or normalized match for "SmartFin Receipts" (ignoring spaces, underscores, hyphens)
      final normalizedTarget = targetAlbumName.replaceAll(RegExp(r'[\s_\-]'), '').toLowerCase();
      for (final album in albums) {
        final norm = album.name.replaceAll(RegExp(r'[\s_\-]'), '').toLowerCase();
        if (norm == normalizedTarget) {
          debugPrint("GalleryWatcher: Matched target album: '${album.name}'");
          return album;
        }
      }

      // 2. Match for keywords: "smartfin", "receipt", "slip", "สลิป"
      for (final album in albums) {
        final lower = album.name.toLowerCase();
        if (lower.contains('smartfin') || lower.contains('receipt') || lower.contains('slip') || lower.contains('สลิป')) {
          debugPrint("GalleryWatcher: Matched keyword album: '${album.name}'");
          return album;
        }
      }

      // 3. Match banking app folders: "K PLUS", "SCB", "Krungthai", "PromptPay", "BBL"
      for (final album in albums) {
        final lower = album.name.toLowerCase();
        if (lower.contains('k plus') || lower.contains('scb') || lower.contains('krungthai') || lower.contains('promptpay') || lower.contains('bbl')) {
          debugPrint("GalleryWatcher: Matched banking folder: '${album.name}'");
          return album;
        }
      }

      // 4. Graceful fallback: If no dedicated slip album exists, use Download or Recent/All
      for (final album in albums) {
        final lower = album.name.toLowerCase();
        if (lower == 'download' || lower == 'recent' || lower == 'recent photos' || album.isAll) {
          debugPrint("GalleryWatcher: Falling back to general album: '${album.name}'");
          return album;
        }
      }

      if (albums.isNotEmpty) {
        return albums.first;
      }

      return null;
    } catch (e) {
      debugPrint('Error finding slips album: $e');
      return null;
    }
  }

  /// Check if there are any new unprocessed slips in the album
  Future<DetectedSlip?> checkForNewSlips() async {
    try {
      final enabled = await isWatcherEnabled();
      if (!enabled) return null;

      final permitted = await requestPermission();
      if (!permitted) return null;

      final album = await findSlipsAlbum();
      if (album == null) {
        debugPrint("GalleryWatcher: Album '$targetAlbumName' not found in gallery yet.");
        return null;
      }

      // Fetch the latest 10 images from the album
      final List<AssetEntity> assets = await album.getAssetListRange(
        start: 0,
        end: 10,
      );

      if (assets.isEmpty) return null;

      final prefs = await SharedPreferences.getInstance();
      final processedIds = (prefs.getStringList(_processedSlipsKey) ?? []).toSet();

      // Find the first unprocessed asset
      for (final asset in assets) {
        if (!processedIds.contains(asset.id)) {
          final File? file = await asset.file;
          if (file != null && await file.exists()) {
            return DetectedSlip(
              asset: asset,
              file: file,
              albumName: album.name,
              createDateTime: asset.createDateTime,
            );
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error checking for new slips: $e');
      return null;
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
