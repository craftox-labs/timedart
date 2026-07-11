import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/shell/keymap.dart';

// The keyboard help modal renders straight from the [Keymap] registry, so it
// can't drift from the handlers — every row here is a binding with
// showInHelp:true, grouped by its helpGroup.

/// One shortcut: its key caps (each string is a cap; a cap may be a combo like
/// "Ctrl+→"; multiple caps read as alternatives) and what it does.
class _Shortcut {
  final List<String> keys;
  final String label;
  const _Shortcut(this.keys, this.label);
}

class _Group {
  final String title;
  final List<_Shortcut> shortcuts;
  const _Group(this.title, this.shortcuts);
}

// Derive the displayed groups from the registry, preserving the order groups
// first appear in the binding list.
List<_Group> _buildGroups() {
  final order = <String>[];
  final byGroup = <String, List<_Shortcut>>{};
  for (final b in Keymap.bindings) {
    if (!b.showInHelp) continue;
    final rows = byGroup.putIfAbsent(b.helpGroup, () {
      order.add(b.helpGroup);
      return [];
    });
    rows.add(_Shortcut(b.caps, b.description));
  }
  return [for (final g in order) _Group(g, byGroup[g]!)];
}

// Split the groups into two columns of roughly equal height (rows + a title
// allowance), keeping their order — so tweaking the keymap can't unbalance it.
List<List<_Group>> _balanceColumns(List<_Group> groups) {
  int weight(_Group g) => g.shortcuts.length + 2; // rows + title + spacing
  final total = groups.fold(0, (sum, g) => sum + weight(g));
  var best = 1, bestDiff = 1 << 30, acc = 0;
  for (var i = 0; i < groups.length - 1; i++) {
    acc += weight(groups[i]);
    final diff = (acc - (total - acc)).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = i + 1;
    }
  }
  return [groups.sublist(0, best), groups.sublist(best)];
}

/// Open the keyboard-shortcuts help. Dismissed with Esc or a click away.
Future<void> showShortcutsHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => const _ShortcutsDialog(),
);

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Wide: two columns so the whole map fits without scrolling. Narrow: a
    // single scrolling column. The split is balanced by row count.
    final wide = MediaQuery.sizeOf(context).width >= AppTokens.breakpointMd;
    final groups = _buildGroups();
    final Widget body;
    if (wide) {
      final columns = _balanceColumns(groups);
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _column(theme, columns[0])),
          const SizedBox(width: AppTokens.space2xl + AppTokens.spaceMd),
          Expanded(child: _column(theme, columns[1])),
        ],
      );
    } else {
      body = _column(theme, groups);
    }

    return CallbackShortcuts(
      // Explicit Esc-to-close (showDialog doesn't bind it by default).
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 720 : 460),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Keyboard shortcuts',
                          style: theme.textTheme.titleLarge,
                        ),
                        const Spacer(),
                        Text('Esc to close', style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                    body,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A vertical stack of groups (title + rows) — one modal column.
  Widget _column(ThemeData theme, List<_Group> groups) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final group in groups) ...[
        Text(
          group.title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        for (final s in group.shortcuts) _row(theme, s),
        const SizedBox(height: AppTokens.spaceLg),
      ],
    ],
  );

  Widget _row(ThemeData theme, _Shortcut s) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Wrap(
            spacing: AppTokens.space3xs,
            runSpacing: AppTokens.space3xs,
            children: [for (final k in s.keys) _cap(theme, k)],
          ),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppTokens.space4xs),
            child: Text(s.label, style: theme.textTheme.bodyMedium),
          ),
        ),
      ],
    ),
  );

  Widget _cap(ThemeData theme, String key) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppTokens.space2xs,
      vertical: AppTokens.space4xs,
    ),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      border: Border.all(color: AppTokens.colorBorder),
    ),
    child: Text(
      key,
      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}
