import 'package:flutter/material.dart';
import 'package:time_tracker/constants/tokens.dart';

/// A panel title bar styled like the side-panel search field — a filled,
/// flush-left / rounded-right bar sitting at the same top inset — but carrying a
/// back arrow and a title instead of an input. Used by settings/branding panels
/// (and any subsequent panel mode) so their header lines up with the search
/// field's position and shape in the normal panel.
class PanelTitleBar extends StatelessWidget {
  const PanelTitleBar({super.key, required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Matches _SearchHeader: flush left, spaceMd right, spaceLg top/bottom.
      padding: const EdgeInsets.fromLTRB(
        0,
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceLg,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(AppTokens.radiusSm),
          ),
        ),
        child: Row(
          children: [
            // Aligned with the search field's prefix icon inset.
            const SizedBox(width: AppTokens.spaceMd),
            IconButton(
              icon: const Icon(Icons.arrow_back, size: AppTokens.iconSm),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Back (Esc)',
              onPressed: onBack,
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Text(
              title,
              style: TextStyle(
                fontSize: AppTokens.fontSizeSm,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
