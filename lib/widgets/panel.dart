import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:timedart/constants/layout.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/widgets/tap_target.dart';

/// The shared building blocks for the app's list side panels — the tracker
/// [SidePanel], the [SettingsPanel], and the docs sidebar. Everything visual a
/// side panel is made of lives here (search field, tiles, list chrome, footer)
/// so the panels stay identical and a change lands in one place; each panel's
/// own file keeps only its data, streams, and keyboard logic.

// ── Search field ────────────────────────────────────────────────────────────

/// The search field pinned to the top of a list panel. Filled, flush-left /
/// rounded-right, with a search prefix and a clear (✕) suffix that appears once
/// there's input. An optional [trailing] widget (e.g. an add button) sits to the
/// right of the field; omit it for panels that add per-section instead.
class PanelSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear; // null when there's nothing to clear
  final VoidCallback onEscape; // Esc hands focus back to the row cursor
  final Widget? trailing; // e.g. an add button; null → field spans the row

  const PanelSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onEscape,
    this.onClear,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Field + clear-button reach a full touch target on narrow; compact on wide.
    final touchMin = context.isNarrow ? AppTokens.minTouchTarget : 36.0;
    // Square left corners so the field sits flush to the panel border;
    // rounded on the right only.
    const fieldRadius = BorderRadius.horizontal(
      right: Radius.circular(AppTokens.radiusSm),
    );
    return Padding(
      // Left flush to the border; right inset matches the rows so a trailing
      // add lands in the edit-button column. Top matches the content pane's
      // spaceLg inset so both panes start at the same height.
      padding: const EdgeInsets.fromLTRB(
        0,
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceLg,
      ),
      child: Row(
        children: [
          Expanded(
            // Esc blurs the field and hands focus back to the row cursor.
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): onEscape,
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: AppTokens.fontSizeSmPlus),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  // Filled, no stroke: the fill gives the flush-left /
                  // rounded-right shape, so there's no left border to leave a
                  // hair against the panel edge.
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  // Icon aligned with the row chevron (~spaceMd from edge).
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(
                      left: AppTokens.spaceMd,
                      right: AppTokens.space2xs,
                    ),
                    child: Icon(Icons.search, size: AppTokens.iconMd),
                  ),
                  prefixIconConstraints: BoxConstraints(minHeight: touchMin),
                  // Same cap as the prefix so the field height doesn't jump when
                  // the clear button appears on input.
                  suffixIconConstraints: BoxConstraints(minHeight: touchMin),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: fieldRadius,
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: fieldRadius,
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: onClear == null
                      ? null
                      : appIconButton(
                          icon: Icons.close,
                          iconSize: AppTokens.iconSm,
                          tooltip: 'Clear search',
                          onPressed: onClear,
                        ),
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTokens.spaceSm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ── Tiles ────────────────────────────────────────────────────────────────────

/// A group header row: chevron + label + optional action(s). Slightly taller
/// than its rows (space2xs of vertical padding) so it reads as the parent. The
/// tile *content* stays in each panel's own widgets; the spacing/density lives
/// here so a change moves every panel in lockstep.
ListTile panelGroupHeaderTile({
  required BuildContext context,
  Widget? leading,
  required Widget title,
  Widget? trailing,
  required VoidCallback onTap,
}) {
  return ListTile(
    dense: true,
    visualDensity: const VisualDensity(vertical: -4),
    // Narrow floors the row at the touch target; desktop lets the content +
    // padding drive the height.
    minTileHeight: context.isNarrow ? AppTokens.minTouchTarget : null,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppTokens.spaceMd,
      vertical: AppTokens.space2xs,
    ),
    horizontalTitleGap: AppTokens.space2xs,
    onTap: onTap,
    leading: leading,
    title: title,
    trailing: trailing,
  );
}

/// An indented row under a header (project, entity, command, doc page). The left
/// inset indents it beneath the header; density matches [panelGroupHeaderTile]
/// but with tighter vertical padding so rows sit close together. Pass [selected]
/// to use the theme's selected-tile highlight.
ListTile panelRowTile({
  required BuildContext context,
  Widget? leading,
  required Widget title,
  Widget? trailing,
  bool selected = false,
  double? horizontalTitleGap,
  required VoidCallback onTap,
}) {
  return ListTile(
    dense: true,
    visualDensity: const VisualDensity(vertical: -4),
    selected: selected,
    minTileHeight: context.isNarrow ? AppTokens.minTouchTarget : null,
    contentPadding: const EdgeInsets.fromLTRB(
      AppTokens.spaceLg,
      AppTokens.space3xs,
      AppTokens.spaceMd,
      AppTokens.space3xs,
    ),
    horizontalTitleGap: horizontalTitleGap,
    leading: leading,
    title: title,
    trailing: trailing,
    onTap: onTap,
  );
}

// ── List chrome ───────────────────────────────────────────────────────────────

/// The vertical padding a side-panel list scrolls within — a hair of breathing
/// room above the first tile and below the last.
const EdgeInsets panelListPadding = EdgeInsets.symmetric(
  vertical: AppTokens.space4xs,
);

/// The hairline rule drawn between one group and the next in a side-panel list.
const Divider panelGroupDivider = Divider(
  height: AppTokens.strokeThin,
  thickness: AppTokens.strokeThin,
  color: AppTokens.colorBorder,
);

/// Wraps a list item with the group chrome: a [panelGroupDivider] above it when
/// it starts a new group, and a gap below when it ends one. Returns [child]
/// untouched when it's neither, so the common case allocates nothing extra.
Widget panelGroupItem({
  required Widget child,
  bool dividerBefore = false,
  bool spacerAfter = false,
}) {
  if (!dividerBefore && !spacerAfter) return child;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (dividerBefore) panelGroupDivider,
      child,
      if (spacerAfter) const SizedBox(height: AppTokens.spaceSm),
    ],
  );
}

/// The left-aligned muted note shown when a side-panel list is empty or a
/// search yields nothing (e.g. "No clients yet", "No matches for …").
class PanelEmptyNote extends StatelessWidget {
  const PanelEmptyNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceXs,
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

/// Base-of-panel footer: a `?` keycap + "Shortcuts" hint (opens the help modal),
/// and a Tracker/Settings switch. Each half is shown only when its callback is
/// set; suppressed in the wide layout, where those actions live in the header.
class PanelFooter extends StatelessWidget {
  const PanelFooter({
    super.key,
    this.onShowHelp,
    this.onOpenSettings,
    this.onOpenTracker,
    this.settingsActive = false,
  });
  final VoidCallback? onShowHelp;
  final VoidCallback? onOpenSettings;
  // Go to the tracker. When set, the timedart symbol shows beside the gear —
  // the two read as a Tracker/Settings switch, mirroring the wide header.
  final VoidCallback? onOpenTracker;
  // Which section is active — tints the tracker/gear pair (primary vs muted).
  final bool settingsActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
            vertical: AppTokens.spaceMd,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onShowHelp != null)
                InkWell(
                  onTap: onShowHelp,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTokens.spaceXs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.space2xs,
                            vertical: AppTokens.space4xs,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusSm,
                            ),
                            border: Border.all(color: AppTokens.colorBorder),
                          ),
                          child: Text(
                            '?',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTokens.spaceXs),
                        Text(
                          'Shortcuts',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (onShowHelp != null &&
                  (onOpenSettings != null || onOpenTracker != null))
                const SizedBox(width: AppTokens.spaceLg),
              if (onOpenTracker != null)
                IconButton(
                  icon: SvgPicture.asset(
                    'assets/logo/timedart_symbol.svg',
                    height: AppTokens.iconSm,
                    colorFilter: ColorFilter.mode(
                      settingsActive ? scheme.onSurfaceVariant : scheme.primary,
                      BlendMode.srcIn,
                    ),
                  ),
                  iconSize: AppTokens.iconSm,
                  visualDensity: context.isNarrow
                      ? VisualDensity.standard
                      : VisualDensity.compact,
                  constraints: context.isNarrow
                      ? const BoxConstraints(
                          minWidth: AppTokens.minTouchTarget,
                          minHeight: AppTokens.minTouchTarget,
                        )
                      : const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  tooltip: 'Tracker',
                  onPressed: onOpenTracker,
                ),
              if (onOpenTracker != null && onOpenSettings != null)
                const SizedBox(width: AppTokens.spaceMd),
              if (onOpenSettings != null)
                IconButton(
                  icon: const Icon(Icons.settings),
                  color: settingsActive
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  iconSize: AppTokens.iconSm,
                  visualDensity: context.isNarrow
                      ? VisualDensity.standard
                      : VisualDensity.compact,
                  constraints: context.isNarrow
                      ? const BoxConstraints(
                          minWidth: AppTokens.minTouchTarget,
                          minHeight: AppTokens.minTouchTarget,
                        )
                      : const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  tooltip: 'Settings',
                  onPressed: onOpenSettings,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
