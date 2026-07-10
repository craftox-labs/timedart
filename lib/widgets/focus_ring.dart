import 'package:flutter/material.dart';
import 'package:timedart/constants/tokens.dart';

/// A thin rectangular ring drawn around the row a keyboard cursor sits on.
/// Square corners so it hugs the row edges; transparent when unfocused so the
/// layout doesn't shift as the cursor moves. Shared by the side panel and the
/// tracker's entry list so both cursors look identical.
class FocusRing extends StatelessWidget {
  final bool focused;
  // When true, only the top and bottom edges are drawn (no left/right). Used
  // by the full-width entry list, where a flush four-sided box hugging the pane
  // edges reads as jarring; the panel keeps the full ring (narrower rows).
  final bool edgesOnly;
  final Widget child;
  const FocusRing({
    super.key,
    required this.focused,
    this.edgesOnly = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = focused
        ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
        : Colors.transparent;
    final side = BorderSide(color: color, width: AppTokens.strokeThin);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: edgesOnly ? Border(top: side, bottom: side) : Border.fromBorderSide(side),
      ),
      child: child,
    );
  }
}
