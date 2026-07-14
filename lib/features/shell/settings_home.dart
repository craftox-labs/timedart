import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timedart/constants/layout.dart';
import 'package:timedart/constants/tokens.dart';

/// The Settings-mode content pane before a Template or Profile has been
/// selected from the side panel. Also the home for future non-invoicing
/// settings once there's more than Templates/Profiles to navigate to.
class SettingsHome extends StatefulWidget {
  const SettingsHome({super.key});

  @override
  State<SettingsHome> createState() => _SettingsHomeState();
}

class _SettingsHomeState extends State<SettingsHome> {
  // Release channel suffix — package_info exposes version + build, not the
  // pre-1.0 `-beta` tag suffix (that lives in the git tag). Drop this at 1.0.
  static const _channel = '-beta';
  static final _websiteUri = Uri.parse('https://timedart.app');

  // Read from the build at runtime (pubspec version), so a new release updates
  // this automatically — no hardcoded string to keep in sync. Empty until the
  // async lookup returns.
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final narrow = context.isNarrow;
    final versionLabel = _version.isEmpty
        ? 'timedart'
        : 'timedart · v$_version$_channel';
    return Column(
      children: [
        // Logo + instruction stay centred in the space above the footer.
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/logo/timedart_logo_stacked.svg',
                  height: narrow ? 140 : 200,
                ),
                const SizedBox(height: AppTokens.spaceXl),
                Text(
                  // Narrow opens the list from the bottom menu, not a side panel.
                  'Select an item from the ${narrow ? 'menu' : 'panel'} to edit.',
                  style: t.textTheme.bodyLarge?.copyWith(
                    color: t.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Links + version pinned to the baseline.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: () => launchUrl(_websiteUri),
              icon: const Icon(Icons.public, size: AppTokens.iconSm),
              label: const Text('Visit website'),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            // Docs don't exist yet — present but disabled so the affordance is
            // there and lights up the day they land.
            Tooltip(
              message: 'Documentation coming soon',
              child: TextButton.icon(
                onPressed: null,
                icon: const Icon(
                  Icons.menu_book_outlined,
                  size: AppTokens.iconSm,
                ),
                label: const Text('Documentation'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMd),
        Text(
          versionLabel,
          style: t.textTheme.labelSmall?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
