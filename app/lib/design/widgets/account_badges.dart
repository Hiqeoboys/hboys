import 'package:flutter/material.dart';

import '../tokens.dart';

/// Lencana "Ultima" untuk akun pemilik Hiqeo Plus seumur hidup (`lifetime`,
/// `founding`, atau `ultima`).
class UltimaBadge extends StatelessWidget {
  const UltimaBadge({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = HiqeoColors.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2B2314) : const Color(0xFF1F2430);
    final fg = isDark ? const Color(0xFFF6D27A) : const Color(0xFFFFD875);
    final border = isDark ? const Color(0xFF7B6027) : const Color(0xFF5A481E);

    return Semantics(
      label: 'Lencana Hiqeo Plus Ultima',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(HiqeoRadius.pill),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.workspace_premium_rounded,
              size: compact ? 13 : 14,
              color: fg,
            ),
            const SizedBox(width: 4),
            Text(
              'Ultima',
              style: TextStyle(
                fontSize: compact ? 10.5 : 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ikon centang terverifikasi untuk akun resmi Hiqeo Official (`@hiqeo`).
class OfficialVerifiedBadge extends StatelessWidget {
  const OfficialVerifiedBadge({
    super.key,
    this.size = 16,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = HiqeoColors.of(context).brightness == Brightness.dark;
    final badgeColor =
        isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

    return Semantics(
      label: 'Akun resmi Hiqeo terverifikasi',
      child: Tooltip(
        message: 'Akun Resmi Hiqeo',
        child: Icon(
          Icons.verified_rounded,
          size: size,
          color: badgeColor,
        ),
      ),
    );
  }
}
