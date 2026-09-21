import 'package:flutter/material.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';

/// Lets the user say which gallery folders Auto-Detect watches.
///
/// No hardcoded list of banking apps can cover every phone: folders are named
/// after whichever app saved the slip ("KPLUS", "SCB EASY"), people rename them,
/// and some save slips as screenshots instead. Selecting nothing keeps the
/// automatic behaviour, which is the right default for most people.
class SlipFoldersSheet extends StatefulWidget {
  const SlipFoldersSheet({super.key});

  /// Returns true when the selection changed, so the caller can rescan.
  static Future<bool> show(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const SlipFoldersSheet(),
    );
    return changed ?? false;
  }

  @override
  State<SlipFoldersSheet> createState() => _SlipFoldersSheetState();
}

class _SlipFoldersSheetState extends State<SlipFoldersSheet> {
  final _watcher = GalleryWatcherService();

  List<GalleryAlbum>? _albums;
  Set<String> _selected = {};
  Set<String> _initial = {};
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selected = await _watcher.selectedAlbumIds();
    final albums = await _watcher.listAlbums();
    if (!mounted) return;
    setState(() {
      _albums = albums;
      // Drop ids for albums that no longer exist, so a stale selection cannot
      // pin the watcher to a folder the user can no longer see or untick.
      _selected = selected.where((id) => albums.any((a) => a.id == id)).toSet();
      _initial = {..._selected};
      _permissionDenied = albums.isEmpty;
    });
  }

  Future<void> _save() async {
    await _watcher.setSelectedAlbumIds(_selected);
    if (!mounted) return;
    final changed = !_setEquals(_selected, _initial);
    Navigator.of(context).pop(changed);
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.every(b.contains);

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    final automatic = _selected.isEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Slip folders', style: AppTextStyles.title),
              const SizedBox(height: AppSpacing.xs),
              Text(
                automatic
                    ? 'SmartFin is watching your banking app folders automatically.'
                    : 'Watching ${_selected.length} folder${_selected.length == 1 ? '' : 's'} you chose.',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (albums == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_permissionDenied)
                const StatusMessage(
                  icon: Icons.photo_library_outlined,
                  title: 'Photo access is off',
                  message:
                      'SmartFin needs photo access to list your folders. You can allow it in your phone settings.',
                )
              else
                Flexible(
                  child: AppCard(
                    flat: true,
                    padding: EdgeInsets.zero,
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      itemCount: albums.length,
                      separatorBuilder: (context, index) =>
                          const Divider(indent: AppSpacing.lg),
                      itemBuilder: (context, i) {
                        final album = albums[i];
                        final checked = _selected.contains(album.id);
                        return CheckboxListTile(
                          value: checked,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                          onChanged: (val) => setState(() {
                            if (val == true) {
                              _selected.add(album.id);
                            } else {
                              _selected.remove(album.id);
                            }
                          }),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  album.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyStrong,
                                ),
                              ),
                              if (album.autoMatched) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.pill,
                                    ),
                                  ),
                                  child: Text(
                                    'Suggested',
                                    style: AppTextStyles.label.copyWith(
                                      fontSize: 12,
                                      color: AppColors.primaryText,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${album.count} photo${album.count == 1 ? '' : 's'}',
                            style: AppTextStyles.caption,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                automatic
                    ? 'Tip: pick a folder yourself if your bank saves slips somewhere we missed.'
                    : 'Untick everything to go back to automatic.',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Done',
                expand: true,
                onPressed: _albums == null ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
