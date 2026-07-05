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
  const PageHeader({super.key, this.alignLogoStart = false});

  /// Left-align the logo inside the bar (instead of centring it over the content
  /// column). Used on settings/branding pages, whose content stretches wider so
  /// a centred logo would drift off the reading column.
  final bool alignLogoStart;

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
                Positioned.fill(
                  child: Align(
                    alignment: alignLogoStart
                        ? Alignment.centerLeft
                        : Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: alignLogoStart
                            ? leftInset + AppTokens.spaceMd
                            : 0,
                      ),
                      child: SvgPicture.asset(
                        'assets/logo/timedart_logo_horizontal.svg',
                        height: 18,
                      ),
                    ),
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
