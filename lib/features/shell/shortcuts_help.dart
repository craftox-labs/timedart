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
  _Group('Panes', [
    _Shortcut(['Tab'], 'Switch pane'),
    _Shortcut(['Ctrl+←', 'Ctrl+→'], 'Focus tracker / panel'),
    _Shortcut(['Ctrl+H', 'Ctrl+L'], 'Focus tracker / panel'),
    _Shortcut(['Ctrl+W', 'H', 'L'], 'Switch pane (vim window motion)'),
    _Shortcut(['/'], 'Focus search'),
    _Shortcut(['?'], 'This help'),
  ]),
  _Group('Side panel', [
    _Shortcut(['J', 'K', '↓', '↑'], 'Move'),
    _Shortcut(['g', 'g', 'G'], 'Top / bottom'),
    _Shortcut(['L', '→'], 'Expand or step in'),
    _Shortcut(['H', '←'], 'Collapse or parent'),
    _Shortcut(['Enter'], 'Select / open job'),
    _Shortcut(['n', 'N'], 'Next / previous job'),
    _Shortcut(['e'], 'Edit client / job'),
    _Shortcut(['Esc'], 'Search → back to list'),
  ]),
  _Group('Tracker', [
    _Shortcut(['J', 'K', '↓', '↑'], 'Move'),
    _Shortcut(['g', 'g', 'G'], 'Top / bottom'),
    _Shortcut(['L', '→'], 'Expand or step in'),
    _Shortcut(['H', '←'], 'Collapse or parent'),
    _Shortcut(['Enter'], 'Arm task / edit entry'),
    _Shortcut(['e'], 'Edit task / entry'),
    _Shortcut(['a'], 'Add task'),
    _Shortcut(['i'], 'Focus description'),
    _Shortcut(['f'], 'Finish session'),
    _Shortcut(['Space'], 'Start / pause / resume (from any pane)'),
    _Shortcut(['Esc'], 'Description → back to list'),
  ]),
  _Group('Editors', [
    _Shortcut(['Enter'], 'Save'),
    _Shortcut(['Esc'], 'Cancel / close'),
  ]),
];

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
            constraints: const BoxConstraints(maxWidth: 460),
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
                        Text(
                          'Esc to close',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                    for (final group in _keymap) ...[
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, _Shortcut s) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Wrap(
            spacing: AppTokens.space3xs,
            runSpacing: AppTokens.space3xs,
            children: [for (final k in s.keys) _cap(theme, k)],
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
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
