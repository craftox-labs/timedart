import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:time_tracker/constants/tokens.dart';

/// The logo bar at the top of the content pane (wide layout). It runs from the
/// content column's left edge across to the divider on the right, so its right
/// edge brackets the panel's search field across the gap while its left edge
/// lines up with the timer / description / task block below. The rounded corner
/// is on the left (the edge away from the divider), mirroring the search field.
///
/// The left inset tracks the content column: [ContentBody] centres its content
/// and caps it at [AppTokens.maxContentWidth] with a [AppTokens.spaceLg] pad, so
/// once the pane is wider than the cap the column gains equal side margins — the
/// header matches them. The logo is centred to the pane, which (because the
/// content column is itself centred) is the same as centring it over the column.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    this.alignLogoStart = false,
    this.onShowHelp,
    this.onOpenSettings,
    this.onOpenTracker,
    this.settingsActive = false,
  });

  /// Left-align the logo inside the bar (instead of centring it over the content
  /// column). Used on settings pages, whose content stretches wider so
  /// a centred logo would drift off the reading column.
  final bool alignLogoStart;

  /// Open the keyboard-shortcuts help. When set, a `?` action shows at the bar's
  /// right edge (just left of the panel divider).
  final VoidCallback? onShowHelp;

  /// Open App Settings. When set, a gear shows in the right cluster.
  final VoidCallback? onOpenSettings;

  /// Go to the tracker. When set, the timedart symbol shows beside the gear —
  /// together they read as a Tracker/Settings switch, the current one primary.
  final VoidCallback? onOpenTracker;

  /// Whether Settings (not the tracker) is the active section — drives which of
  /// the two nav icons is tinted primary vs muted.
  final bool settingsActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        // Left edge of the centred, capped content column, relative to the pane.
        final margin = ((c.maxWidth - AppTokens.maxContentWidth) / 2).clamp(
          0.0,
          double.infinity,
        );
        final leftInset = margin + AppTokens.spaceLg;
        return Padding(
          // Top inset matches the search field so the bars line up. The bottom
          // is small on purpose: the content pane adds its own spaceLg top, so
          // the header→content gap ends up equal to the panel's search→first-row
          // gap (a spaceLg plus the list's small inset) rather than double it.
          padding: const EdgeInsets.only(
            top: AppTokens.spaceLg,
            bottom: AppTokens.space4xs,
          ),
          child: SizedBox(
            height: 36,
            child: Stack(
              children: [
                // The bar itself: from the content's left edge across to the
                // divider.
                Positioned(
                  left: leftInset,
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(AppTokens.radiusSm),
                      ),
                    ),
                  ),
                ),
                // Logo centred to the pane (== centred over the centred content
                // column), or left-aligned inside the bar on settings pages.
                // Logo: centred over the content column on the tracker, sliding
                // to the bar's left edge on settings/invoice pages. Both the
                // alignment and the inset animate so it glides across on the
                // tracker↔settings transition instead of snapping.
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: alignLogoStart
                        ? Alignment.centerLeft
                        : Alignment.center,
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      // Inset off the bar's left edge so the logo has breathing
                      // room. The stretch content pane (adaptive_shell) adds the
                      // SAME leftInset + spaceMd to its left pad, so the logo
                      // stays aligned with the title/fields below. Keep in sync.
                      padding: EdgeInsets.only(
                        left: alignLogoStart ? leftInset + AppTokens.spaceMd : 0,
                      ),
                      child: SvgPicture.asset(
                        'assets/logo/timedart_logo_horizontal.svg',
                        height: 18,
                      ),
                    ),
                  ),
                ),
                // Shortcuts + Tracker/Settings switch at the bar's right edge —
                // just left of the panel divider. Icon-only; the tooltip carries
                // the label + key. The tracker/gear pair tint to show the active
                // section (primary) vs the other (muted); `?` stays muted.
                if (onShowHelp != null ||
                    onOpenSettings != null ||
                    onOpenTracker != null)
                  Positioned(
                    right: AppTokens.spaceMd,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onOpenTracker != null)
                          _HeaderAction(
                            icon: SvgPicture.asset(
                              'assets/logo/timedart_symbol.svg',
                              height: AppTokens.iconSm,
                              colorFilter: ColorFilter.mode(
                                settingsActive
                                    ? scheme.onSurfaceVariant
                                    : scheme.primary,
                                BlendMode.srcIn,
                              ),
                            ),
                            tooltip: 'Tracker  (t)',
                            onPressed: onOpenTracker!,
                          ),
                        if (onShowHelp != null)
                          _HeaderAction(
                            icon: Icon(
                              Icons.help_outline,
                              size: AppTokens.iconMd,
                              color: scheme.onSurfaceVariant,
                            ),
                            tooltip: 'Shortcuts  (?)',
                            onPressed: onShowHelp!,
                          ),
                        if (onOpenSettings != null)
                          _HeaderAction(
                            icon: Icon(
                              Icons.settings,
                              size: AppTokens.iconMd,
                              color: settingsActive
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            tooltip: 'Settings  (Ctrl+,)',
                            onPressed: onOpenSettings!,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A compact icon button sized to sit inside the 36px header bar. Takes a
/// pre-built [icon] widget so callers control size + colour (Material icon or
/// tinted SVG).
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final Widget icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: icon,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: AppTokens.space2xs),
    constraints: const BoxConstraints(),
    onPressed: onPressed,
  );
}
