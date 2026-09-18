import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The title line at the top of every tab screen (History, AI Coach, Profile),
/// so titles sit in the same place with the same type on each. Left-aligned to
/// match the SmartFin logo on the dashboard, with an optional 40px action on
/// the right. Callers supply the blurred header bar and its 24px side and 48px
/// top insets.
class PageTitleRow extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const PageTitleRow({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: const Color(0xFF333333),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
