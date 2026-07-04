import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:time_tracker/constants/tokens.dart';

/// The app's top header strip (wide layout). It sits *above* the tracker |
/// side-panel split and adds nothing to their behaviour.
///
/// The left region mirrors [ContentBody]'s geometry (centred, capped at
/// [AppTokens.maxContentWidth], inset by [AppTokens.spaceLg]) so the logo's
/// left edge lands on the same content inset as the pane below it. The trailing
/// [dividerWidth] + [panelWidth] spacers reproduce the split's right-hand
/// columns, so the strip's right end lines up with the panel's search column.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.panelWidth,
    required this.dividerWidth,
  });

  final double panelWidth;
  final double dividerWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTokens.maxContentWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceLg,
                  vertical: AppTokens.spaceSm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  // The horizontal logo already carries the "timedart"
                  // wordmark, so no separate name text is needed.
                  child: SvgPicture.asset(
                    'assets/logo/timedart_logo_horizontal.svg',
                    height: 26,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Reproduce the split's right columns so the left region matches the
        // content pane's Expanded region exactly (and the strip's right end
        // aligns with the search column).
        SizedBox(width: dividerWidth),
        SizedBox(width: panelWidth),
      ],
    );
  }
}
