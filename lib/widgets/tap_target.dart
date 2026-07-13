import 'package:flutter/material.dart';
import 'package:timedart/constants/layout.dart';
import 'package:timedart/constants/tokens.dart';

/// Wraps a small tappable glyph (a chevron, a bare icon) so its hit area is at
/// least [AppTokens.minTouchTarget] on narrow/touch layouts, while staying
/// visually and behaviourally unchanged on wide/desktop layouts.
class TapTarget extends StatelessWidget {
  const TapTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: context.isNarrow
          ? SizedBox.square(
              dimension: AppTokens.minTouchTarget, // 48
              child: Center(child: child),
            )
          : child, // wide: hug the glyph exactly as before
    );
    if (tooltip != null) result = Tooltip(message: tooltip!, child: result);
    return result;
  }
}

/// An [IconButton] that hugs its glyph on wide/desktop layouts but expands to a
/// full [AppTokens.minTouchTarget] hit box on narrow/touch layouts.
Widget appIconButton({
  required IconData icon,
  required VoidCallback? onPressed,
  String? tooltip,
  double iconSize = AppTokens.iconMd,
  Color? color,
}) {
  return Builder(
    builder: (context) {
      final narrow = context.isNarrow;
      return IconButton(
        icon: Icon(icon, color: color),
        iconSize: iconSize,
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        // compact density shaves 8px off the min box, so on narrow we drop to
        // standard or the 48 floor below would only resolve to 40.
        visualDensity: narrow ? VisualDensity.standard : VisualDensity.compact,
        constraints: narrow
            ? const BoxConstraints(
                minWidth: AppTokens.minTouchTarget,
                minHeight: AppTokens.minTouchTarget,
              )
            : const BoxConstraints(),
      );
    },
  );
}
