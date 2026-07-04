import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:time_tracker/constants/tokens.dart';

/// The logo bar at the top of the content pane (wide layout). It mirrors the
/// side-panel's search field: same fill and height, sitting at the same top
/// inset so the two bars bracket the divider.
///
/// The bar runs to the divider on the right, with a left gap that mirrors the
/// space between the panel's search input and its right edge (the trailing gap
/// + add button + panel right padding). The rounded corner is on the left —
/// the edge away from the divider — mirroring the search field. The logo is
/// centred to the content pane (which is itself centred within the region), so
/// it sits over the timer/content column below.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key});

  // Left gap = the panel's search-input-to-right-edge space: the SizedBox gap,
  // the add button (iconMd), and the panel's right padding (spaceMd).
  static const double _leftGap =
      AppTokens.spaceSm + AppTokens.iconMd + AppTokens.spaceMd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Top/bottom inset matches the search field so the bars line up and the
      // gap below equals the gap above.
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceLg),
      child: SizedBox(
        height: 36,
        child: Stack(
          children: [
            // The bar itself: from the left gap across to the divider.
            Positioned(
              left: _leftGap,
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
            // Logo centred to the content pane (region centre), so it lines up
            // over the centred content column below. The horizontal logo
            // already carries the "timedart" wordmark.
            Positioned.fill(
              child: Center(
                child: SvgPicture.asset(
                  'assets/logo/timedart_logo_horizontal.svg',
                  height: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
