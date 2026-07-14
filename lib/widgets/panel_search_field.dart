import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/constants/layout.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/widgets/tap_target.dart';

/// The search field pinned to the top of a list panel — shared by the tracker
/// [SidePanel] and the [SettingsPanel] so both look and behave identically.
///
/// Filled, flush-left / rounded-right, with a search prefix and a clear (✕)
/// suffix that appears once there's input. An optional [trailing] widget (e.g.
/// an add button) sits to the right of the field; omit it for panels that add
/// per-section instead (Settings).
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
                style: const TextStyle(fontSize: AppTokens.fontSizeSm),
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
                      right: AppTokens.spaceXs,
                    ),
                    child: Icon(Icons.search, size: AppTokens.iconSm),
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
