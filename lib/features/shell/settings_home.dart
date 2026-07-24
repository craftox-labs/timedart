import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/docs/docs_screen.dart';

/// The Settings-mode content pane before a Template or Profile has been
/// selected from the side panel. Also the home for future non-invoicing
/// settings once there's more than Templates/Profiles to navigate to.
class SettingsHome extends StatefulWidget {
  const SettingsHome({super.key, this.footerOnly = false});

  /// When true, render only the links + version footer (no logo / no "select
  /// an item" prompt) — used as the footer beneath the narrow full-page
  /// Settings list, where the sections themselves are the screen. The full
  /// placeholder (logo + prompt + footer) is the wide content-pane home.
  final bool footerOnly;

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
    final versionLabel = _version.isEmpty
        ? 'timedart'
        : 'timedart · v$_version$_channel';

    final linksRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: () => launchUrl(_websiteUri),
          icon: const Icon(Icons.public, size: AppTokens.iconSm),
          label: const Text('Visit website'),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        TextButton.icon(
          onPressed: () => openDocs(context),
          icon: const Icon(Icons.menu_book_outlined, size: AppTokens.iconSm),
          label: const Text('Documentation'),
        ),
      ],
    );
    final versionText = Text(
      versionLabel,
      style: t.textTheme.labelSmall?.copyWith(
        color: t.colorScheme.onSurfaceVariant,
      ),
    );

    // Narrow full-page Settings footer: compact, version on top with the links
    // beneath it — the sections list above is the screen, so this stays short.
    if (widget.footerOnly) {
      return Padding(
        // Equal breathing room above and below the links (matching gaps), so
        // they clear the bottom nav bar and stay comfortably tappable.
        padding: const EdgeInsets.only(
          top: AppTokens.spaceXs,
          bottom: AppTokens.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            versionText,
            const SizedBox(height: AppTokens.spaceLg),
            linksRow,
          ],
        ),
      );
    }

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
                  height: 200,
                ),
                const SizedBox(height: AppTokens.spaceXl),
                Text(
                  // Full placeholder is the wide content pane only; narrow
                  // renders the sections list itself (see AdaptiveShell).
                  'Select an item from the panel to edit.',
                  style: t.textTheme.bodyLarge?.copyWith(
                    color: t.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Links + version pinned to the baseline of the placeholder.
        linksRow,
        const SizedBox(height: AppTokens.spaceMd),
        versionText,
      ],
    );
  }
}
