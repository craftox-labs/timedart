import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/constants/tokens.dart';

// The single source of truth for the keyboard help modal. The real handlers
// (adaptive_shell / side_panel / timer_view) still switch on their own keys, so
// keep this table in step when a binding changes — it's what `?` renders.

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

const List<_Group> _keymap = [
  // Movement, open/collapse, edit and Enter behave the same in both the side
  // panel and the tracker, so they live here once instead of per pane.
  _Group('Navigation', [
    _Shortcut(['J', 'K', '↓', '↑'], 'Move'),
    _Shortcut(['g', 'g', 'G'], 'Top / bottom'),
    _Shortcut(['L', '→'], 'Open / expand'),
    _Shortcut(['H', '←'], 'Collapse / parent'),
    _Shortcut(['Enter'], 'Select / activate'),
    _Shortcut(['e'], 'Edit focused item'),
    _Shortcut(['Esc'], 'Back to list'),
  ]),
  _Group('Panes', [
    _Shortcut(['Tab'], 'Switch pane'),
    _Shortcut(['Ctrl+←', 'Ctrl+→'], 'Focus tracker / panel'),
    _Shortcut(['Ctrl+W', 'H', 'L'], 'Switch pane (vim)'),
    _Shortcut(['/'], 'Search'),
    _Shortcut(['?'], 'This help'),
  ]),
  _Group('Side panel', [
    _Shortcut(['a'], 'Add job'),
    _Shortcut(['A'], 'Add client'),
    _Shortcut(['n', 'N'], 'Next / previous job'),
  ]),
  _Group('Tracker', [
    _Shortcut(['Space'], 'Start / pause / resume'),
    _Shortcut(['f'], 'Finish session'),
    _Shortcut(['a'], 'Add task'),
    _Shortcut(['A'], 'Add entry'),
    _Shortcut(['i'], 'Focus description'),
  ]),
  _Group('Editors', [
    _Shortcut(['Enter'], 'Save'),
    _Shortcut(['Esc'], 'Cancel / close'),
  ]),
];

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
    final Widget body;
    if (wide) {
      final columns = _balanceColumns(_keymap);
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _column(theme, columns[0])),
          const SizedBox(width: AppTokens.space2xl + AppTokens.spaceMd),
          Expanded(child: _column(theme, columns[1])),
        ],
      );
    } else {
      body = _column(theme, _keymap);
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
      style: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
