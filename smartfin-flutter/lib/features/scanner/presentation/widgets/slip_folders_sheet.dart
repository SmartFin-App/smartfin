import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_fin/constants/color_style.dart';
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
      backgroundColor: Colors.transparent,
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

    return Container(
      padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Slip folders',
              style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.5,
                color: const Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              automatic
                  ? 'SmartFin is watching your banking app folders automatically.'
                  : 'Watching ${_selected.length} folder${_selected.length == 1 ? '' : 's'} you chose.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: const Color(0xFF9E9E9E),
              ),
            ),
            const SizedBox(height: 16),
            if (albums == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_permissionDenied)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'SmartFin needs photo access to list your folders. '
                  'You can allow it in your phone settings.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics()),
                  itemCount: albums.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: const Color.fromRGBO(234, 226, 214, 0.3),
                  ),
                  itemBuilder: (context, i) {
                    final album = albums[i];
                    final checked = _selected.contains(album.id);
                    return CheckboxListTile(
                      value: checked,
                      activeColor: const Color(0xFFFF9F29),
                      contentPadding: EdgeInsets.zero,
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
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: const Color(0xFF333333),
                              ),
                            ),
                          ),
                          if (album.autoMatched) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(255, 159, 41, 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Suggested',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  color: const Color(0xFFFF9F29),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '${album.count} photo${album.count == 1 ? '' : 's'}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Text(
              automatic
                  ? 'Tip: pick a folder yourself if your bank saves slips somewhere we missed.'
                  : 'Untick everything to go back to automatic.',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: const Color(0xFF9E9E9E),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _albums == null ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9F29),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Done',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
