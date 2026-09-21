import 'package:flutter/material.dart';
import 'package:smart_fin/constants/color_style.dart';

/// An icon on a rounded square tinted with its own colour — the leading mark
/// of a category, bill or setting row.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}
