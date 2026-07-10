import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:timedart/constants/tokens.dart';

/// The Settings-mode content pane before a Template or Profile has been
/// selected from the side panel. Also the home for future non-invoicing
/// settings once there's more than Templates/Profiles to navigate to.
class SettingsHome extends StatelessWidget {
  const SettingsHome({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/logo/timedart_logo_stacked.svg',
            height: 240,
          ),
          const SizedBox(height: AppTokens.spaceXl),
          Text(
            'Select an item from the panel to edit.',
            style: t.textTheme.bodyLarge?.copyWith(
              color: t.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
