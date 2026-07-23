import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timedart/features/updates/update_checker.dart';
import 'package:timedart/widgets/markdown_style.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/backup.dart';
import 'package:timedart/data/sync/delta/auth_service.dart';
import 'package:timedart/data/sync/delta/delta_config.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/sync_controller.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';
import 'package:timedart/util/save_file.dart';
import 'package:timedart/util/pick_file.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/shell/keymap.dart';
import 'package:timedart/features/shell/page_header.dart';
import 'package:timedart/features/shell/shortcuts_help.dart';
import 'package:timedart/features/shell/side_panel.dart';
import 'package:timedart/features/shell/settings_panel.dart';
import 'package:timedart/features/tracker/timer_view.dart';
import 'package:timedart/features/projects/project_form.dart';
import 'package:timedart/features/clients/client_form.dart';
import 'package:timedart/features/invoices/invoice_view.dart';
import 'package:timedart/features/invoices/editor_session.dart';
import 'package:timedart/features/invoices/profile_editor.dart';
import 'package:timedart/features/invoices/template_editor.dart';
import 'package:timedart/features/shell/settings_home.dart';
import 'package:timedart/widgets/confirm_dialog.dart';
import 'package:timedart/widgets/content_body.dart';
import 'package:timedart/widgets/sheet_grab_handle.dart';
import 'package:animations/animations.dart';

// What the detail pane is currently showing. One value instead of a pile of
// nullable flags, so the content is a single exhaustive switch.
sealed class _Detail {
  const _Detail();
}

class _Tracker extends _Detail {
  const _Tracker();
}

class _Invoice extends _Detail {
  final Project project;
  const _Invoice(this.project);
}

// App Settings home: the panel shows template/profile sections; the content
// pane is a placeholder until one is picked (see SettingsHome).
class _Settings extends _Detail {
  const _Settings();
}

// Editing (or creating, when the row is null) a template or profile in the content
// pane, with the settings panel still alongside.
class _TemplateEditorDetail extends _Detail {
  final InvoiceTemplate? template;
  final bool startEditing; // the 'e' shortcut skips straight past the view
  const _TemplateEditorDetail(this.template, {this.startEditing = false});
}

class _ProfileEditorDetail extends _Detail {
  final InvoiceProfile? profile;
  final bool startEditing;
  const _ProfileEditorDetail(this.profile, {this.startEditing = false});
}

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({
    super.key,
    required this.db,
    this.onRerunOnboarding,
    this.initialSelectedProjectId,
  });
  final AppDatabase db;
  // Settings → "Re-run setup": replays the first-run onboarding flow. Wired by
  // the root gate; null when the shell is mounted without one.
  final Future<void> Function()? onRerunOnboarding;
  // The project to select on the first frame. The root gate already resolves
  // the default project while bootstrapping, so passing it here avoids the
  // tracker painting an empty (no-selection) frame that then pops to content.
  final String? initialSelectedProjectId;
  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String? _selectedProjectId; // the project the timer records against
  _Detail _detail = const _Tracker();
  // Narrow layout only: whether the project/settings list overlay is open. The
  // bottom bar's centre button toggles it; the bar stays live underneath. This
  // is the *intent* flag (drives the bar's styling and pointer-gating); the
  // sheet's actual position is [_sheetCtrl] so a drag can track the finger.
  bool _panelOpen = false;
  // 0 = sheet fully closed (off-screen bottom), 1 = fully open. Programmatic
  // open/close eases via animateTo; a handle drag writes .value directly for
  // finger-follow, then _settleSheet flings to the nearer end on release.
  late final AnimationController _sheetCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  // Linear (uncurved) so a drag maps 1:1 to the finger; the ease is applied per
  // programmatic call instead. Offset(0,1) = translated fully below its slot.
  late final Animation<Offset> _sheetOffset = Tween(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_sheetCtrl);
  StreamSubscription<List<Project>>? _projectsSub;

  // The currently-mounted Template/Profile editor's lifecycle (dirty + save),
  // handed up by the editor itself via onSessionReady. Its `isDirty` gates every
  // _detail transition through _navigateTo, and `save()` runs the unsaved-changes
  // dialog's Save. Null outside those two editors.
  EditorSession? _activeEditor;

  // Settings mode swaps the side panel for the settings sections.
  bool get _inSettings =>
      _detail is _Settings ||
      _detail is _TemplateEditorDetail ||
      _detail is _ProfileEditorDetail;
  // Pages whose content stretches to the divider with a left-aligned header
  // logo — the settings pages plus the per-project invoice view (a preview page too).
  bool get _wideContentPage => _inSettings || _detail is _Invoice;

  // Content stretches to the divider only where a live invoice preview needs the
  // width — the two editors and the per-project invoice. The Settings home is a
  // centred placeholder, so it uses ContentBody's 800px column like the tracker.
  bool get _stretchContent =>
      _detail is _TemplateEditorDetail ||
      _detail is _ProfileEditorDetail ||
      _detail is _Invoice;

  // Keyboard-nav focus (wide layout only). The panel's row cursor lives here so
  // the shell can move focus *into* the panel; the tracker pane is a scope we
  // hand focus to (its own widgets take over from there — content-pane keymap
  // is a follow-up, see issue).
  final FocusNode _panelCursor = FocusNode(debugLabel: 'panelCursor');
  final FocusNode _settingsCursor = FocusNode(debugLabel: 'settingsCursor');
  final FocusScopeNode _trackerScope = FocusScopeNode(
    debugLabel: 'trackerScope',
  );
  // The tracker pane's own row cursor (its entry list). Owned here so the shell
  // can move focus straight onto it — mirrors _panelCursor. See TimerView.
  final FocusNode _trackerCursor = FocusNode(debugLabel: 'trackerCursor');
  // Panel search fields, owned here so `/` from any pane jumps into search —
  // one per pane (client/project tree vs Settings), picked by _inSettings.
  final FocusNode _panelSearch = FocusNode(debugLabel: 'panelSearch');
  final FocusNode _settingsSearch = FocusNode(debugLabel: 'settingsSearch');
  // Lets a global Space toggle the timer from any pane while it's in view.
  // DB-backed (Phase 3) — constructed with the db and recovered in initState.
  late final TimerController _timer;
  // Automatic delta-sync scheduling + status (Phase 5c, #294). Non-null only in
  // a maintainer's ENABLE_DELTA_SYNC build; released builds leave it null and
  // never observe lifecycle or schedule a tick.
  SyncController? _sync;
  // Chord state for global sequences (the Ctrl-w window motion) when focus is
  // on a pane that bubbles them here (e.g. the content editors). The list panes
  // own their own detectors and forward focusTracker/focusPanel via callbacks.
  final ChordDetector _shellChords = ChordDetector();

  void _focusPanel() =>
      (_inSettings ? _settingsCursor : _panelCursor).requestFocus();
  void _focusTracker() => _trackerCursor.requestFocus();
  void _focusSearch() =>
      (_inSettings ? _settingsSearch : _panelSearch).requestFocus();

  // Is a text field currently focused? EditableText wraps its focusNode in a
  // Focus whose context sits under the EditableText widget, so the primary
  // focus resolves an EditableText ancestor exactly when we're typing.
  bool _isEditing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // "In the panel" means either its row cursor or its search field has focus —
  // otherwise Tab out of a focused search would wrongly jump to the tracker.
  void _togglePane() =>
      (_panelCursor.hasFocus ||
          _settingsCursor.hasFocus ||
          _panelSearch.hasFocus ||
          _settingsSearch.hasFocus)
      ? _focusTracker()
      : _focusPanel();

  // Global bindings live at the shell: Tab, Ctrl+←/→, Ctrl-h/l, the vim
  // Ctrl-w h/l chord, `?`/`/`/`t`/Space/Ctrl+,. Reached for events the focused
  // pane bubbles (a list pane owns pane-switching for its own focus, forwarding
  // via onFocusTracker/onFocusPanel; the content editors bubble to here).
  KeyEventResult _onShellKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Printable globals (`?`, `/`, Space, `t`, Tab) must stand down while a text
    // field is focused — those events still bubble up here as the field types.
    final r = Keymap.resolve(
      event,
      _shellChords,
      const {KeyScope.global},
      ctrlDown: HardwareKeyboard.instance.isControlPressed,
      shiftDown: HardwareKeyboard.instance.isShiftPressed,
      typing: _isEditing(),
    );
    switch (r) {
      case KeyPending():
        return KeyEventResult.handled;
      case KeyNone():
        return KeyEventResult.ignored;
      case KeyMatch(:final intent):
        if (event is KeyDownEvent) _handleGlobalIntent(intent);
        return KeyEventResult.handled;
    }
  }

  // Layout is tracker (left) | sidebar (right), so direction follows position:
  // left (focusTracker) → tracker, right (focusPanel) → panel.
  void _handleGlobalIntent(KeyIntent intent) {
    switch (intent) {
      case KeyIntent.showHelp:
        showShortcutsHelp(context);
      case KeyIntent.search:
        _focusSearch();
      case KeyIntent.openTracker:
        if (_detail is! _Tracker) _showTracker();
      case KeyIntent.toggleTimer:
        if (_detail is _Tracker) _timer.primary?.call();
      case KeyIntent.openSettings:
        _openSettings();
      case KeyIntent.focusTracker:
        _focusTracker();
      case KeyIntent.focusPanel:
        _focusPanel();
      case KeyIntent.switchPane:
        _togglePane();
      default:
        break; // non-global intents never resolve under the global scope
    }
  }

  // The single gate every _detail transition goes through, so an unsaved
  // change in the open Template/Profile editor can never be silently
  // discarded. No-ops if `next` targets the entity already open.
  Future<void> _navigateTo(_Detail next) async {
    final cur = _detail;
    final sameEntity = switch ((cur, next)) {
      (_TemplateEditorDetail c, _TemplateEditorDetail n) =>
        c.template?.id == n.template?.id,
      (_ProfileEditorDetail c, _ProfileEditorDetail n) =>
        c.profile?.id == n.profile?.id,
      _ => false,
    };
    if (sameEntity) return;
    if (_activeEditor?.isDirty ?? false) {
      final action = await confirmUnsavedChanges(context);
      if (action == null) return; // stay put, keep editing
      if (action == UnsavedChangesAction.save) {
        final ok = await _activeEditor?.save() ?? true;
        if (!ok) return; // validation failed; stay on the editor
      }
    }

    if (!mounted) return;
    final wasInSettings = _inSettings; // reads the *old* _detail
    setState(() {
      _detail = next;
      _activeEditor = null;
    });
    // The panel's PageTransitionSwitcher swaps only when _inSettings flips, and
    // that swap drops keyboard focus to the root scope (the outgoing panel holds
    // it through the crossfade, so the incoming panel's autofocus is lost).
    // Re-assert focus on the now-active panel so shell shortcuts (?, t, Space)
    // have a focused descendant to bubble from. Only on the boundary, so it
    // doesn't yank focus away from an editor opened within settings.
    if (_inSettings != wasInSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusPanel();
      });
    }
  }

  void _showTracker() => _navigateTo(const _Tracker());
  void _selectProject(String id) => setState(() {
    _selectedProjectId = id;
    _detail = const _Tracker(); // picking a project returns you to the timer
  });

  // Client/project editing are modals (like task/entry), so they open over the
  // content pane rather than replacing it.
  void _editProject(Project project) =>
      showProjectEditor(context, db: widget.db, project: project);
  Future<void> _addProject(String clientId) async {
    final createdProjectId = await showProjectEditor(
      context,
      db: widget.db,
      initialClientId: clientId,
    );
    // A freshly-created project becomes the selection so the timer switches to it.
    if (createdProjectId != null && mounted) _selectProject(createdProjectId);
  }

  void _editClient(Client c) =>
      showClientEditor(context, db: widget.db, client: c);
  void _addClient() => showClientEditor(context, db: widget.db);
  void _invoiceProject(Project project) =>
      setState(() => _detail = _Invoice(project));

  // Export the whole database to a portable JSON backup the user chooses a
  // location for (PRD #189, #190). Captures the messenger before the awaits so
  // it survives the async gap, and guards on `mounted` after.
  Future<void> _exportData() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await exportBackupBytes(
        widget.db,
        exportedAt: DateTime.now(),
      );
      final date = DateTime.now().toIso8601String().split('T').first;
      final saved = await saveBytes(
        bytes,
        suggestedName: 'timedart-backup-$date.json',
        typeLabel: 'JSON backup',
        extensions: const ['json'],
        mimeType: 'application/json',
      );
      if (!mounted) return;
      if (saved != null) {
        messenger.showSnackBar(const SnackBar(content: Text('Data exported.')));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  // Import a backup, replacing all data (PRD #189, #191). Pick → decode →
  // confirm (replace-all is destructive) → restore → reset to a safe view.
  Future<void> _importData() async {
    final messenger = ScaffoldMessenger.of(context);
    final PickedFile? picked;
    try {
      picked = await pickFileBytes(
        typeLabel: 'JSON backup',
        extensions: const ['json'],
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open file: $e')),
      );
      return;
    }
    if (picked == null) return; // cancelled
    if (!mounted) return;

    final Backup backup;
    try {
      backup = decodeBackup(picked.bytes);
    } on BackupFormatException catch (e) {
      await showInfoDialog(
        context,
        title: 'Invalid backup',
        message: "That file isn't a valid timedart backup.\n\n${e.message}",
      );
      return;
    }

    if (!mounted) return;
    final s = backup.snapshot;
    final confirmed = await confirmAction(
      context,
      title: 'Replace all data?',
      message:
          'Importing "${picked.name}" deletes everything currently in timedart '
          'and replaces it with the backup:\n\n'
          '• ${s.clients.length} clients\n'
          '• ${s.projects.length} projects\n'
          '• ${s.tasks.length} tasks\n'
          '• ${s.timeEntries.length} time entries\n\n'
          'This cannot be undone.',
      confirmLabel: 'Replace',
    );
    if (!confirmed || !mounted) return;

    final SnapshotRepair repair;
    try {
      repair = await restoreBackup(widget.db, backup);
    } on BackupIncompatibleException catch (e) {
      if (!mounted) return;
      await showInfoDialog(
        context,
        title: 'Newer backup',
        message:
            'This backup was made by a newer version of timedart '
            '(schema v${e.backupSchemaVersion}). Update the app, then import '
            'again.',
      );
      return;
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      return;
    }
    if (!mounted) return;
    // The selected project may no longer exist; drop it and return to the
    // tracker — the build re-defaults selection from the refreshed stream.
    setState(() => _selectedProjectId = null);
    _showTracker();
    final skipped = repair.isClean
        ? ''
        : ' Skipped ${repair.total} orphaned row(s) from earlier deleted '
              'projects.';
    messenger.showSnackBar(SnackBar(content: Text('Data imported.$skipped')));
  }

  // ── Update check (Phase 1: notify only — never auto-installs) ──────────────
  // Guards the launch banner to at most once per run.
  bool _updateBannerShown = false;

  // Silent launch check: if a newer release exists, surface a non-blocking,
  // dismissible banner. Failures (offline, rate-limited) are swallowed.
  Future<void> _autoCheckForUpdates() async {
    final status = await UpdateChecker().check();
    if (!mounted || _updateBannerShown || status is! UpdateAvailable) return;
    _updateBannerShown = true;
    final messenger = ScaffoldMessenger.of(context);
    final release = status.release;
    void dismiss() => messenger.hideCurrentMaterialBanner();

    final message = Text('timedart ${release.tag} is available.');
    final buttons = [
      TextButton(onPressed: dismiss, child: const Text('Later')),
      const SizedBox(width: AppTokens.spaceSm),
      FilledButton(
        onPressed: () {
          dismiss();
          _showUpdateDialog(release);
        },
        child: const Text('View'),
      ),
    ];

    // Both buttons live in the banner's content (not its actions) so we own the
    // layout: a single row on desktop; on a narrow screen the text stacks with
    // the buttons left-aligned beneath it. A zero-size phantom action satisfies
    // MaterialBanner's non-empty `actions` without it adding a second row.
    final narrow = MediaQuery.sizeOf(context).width < AppTokens.breakpointMd;
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update_alt),
        forceActionsBelow: false,
        actions: const [SizedBox.shrink()],
        content: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  message,
                  const SizedBox(height: AppTokens.spaceSm),
                  Row(mainAxisSize: MainAxisSize.min, children: buttons),
                ],
              )
            : Row(
                children: [
                  Expanded(child: message),
                  const SizedBox(width: AppTokens.spaceMd),
                  ...buttons,
                ],
              ),
      ),
    );
  }

  // Settings → "Check for updates": an explicit check with feedback for every
  // outcome.
  Future<void> _checkForUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Checking for updates…')),
    );
    final status = await UpdateChecker().check();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    switch (status) {
      case UpdateAvailable(:final release):
        await _showUpdateDialog(release);
      case UpToDate():
        messenger.showSnackBar(
          const SnackBar(content: Text("You're on the latest version.")),
        );
      case DevBuild(:final latest):
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              latest == null
                  ? 'Development build — updates are not tracked.'
                  : 'Development build. Latest release is ${latest.tag}.',
            ),
          ),
        );
      case CheckFailed(:final reason):
        messenger.showSnackBar(SnackBar(content: Text(reason)));
    }
  }

  // Run one delta-sync pass on demand (Phase 5a, #294; routed through the 5c
  // controller so it coalesces with any background pass in flight). Maintainer-
  // only (ENABLE_DELTA_SYNC). Unlike the background triggers this one reports —
  // a snackbar makes the 2-device verify observable in-app.
  Future<void> _syncNow() async {
    final sync = _sync;
    if (sync == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Syncing…')));
    await sync.syncNow();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(_syncResultText(sync))));
  }

  // Human-readable outcome of the controller's last pass, shared by "Sync now"
  // and the enable flow.
  String _syncResultText(SyncController sync) {
    final result = sync.lastResult;
    if (sync.lastError != null) return 'Sync failed: ${sync.lastError}';
    if (result == null) return 'Sync did not run.';
    if (result.needsSignIn) {
      return 'Sign in to an account (Account…) to sync.';
    }
    if (result.didSync) {
      return 'Synced — pushed ${result.pushed}, applied ${result.applied} of '
          '${result.pulled} pulled.';
    }
    return 'Sync skipped — ${result.skippedReason}.';
  }

  // Opt in / out of delta sync (Phase 5d, #294). Persists the flag, then flips
  // the controller: enabling arms scheduling and kicks a first pass (sign-in +
  // adoption of offline-created local rows); disabling stops future passes but
  // keeps the session and all local data, so re-enabling resumes the same
  // account. Maintainer-only.
  Future<void> _toggleDeltaSync() async {
    final sync = _sync;
    if (sync == null) return;
    final turnOn = !sync.enabled;
    final messenger = ScaffoldMessenger.of(context);
    await widget.db.setSyncSetting(kSyncEnabled, turnOn ? '1' : '0');
    if (turnOn) {
      messenger.showSnackBar(const SnackBar(content: Text('Enabling sync…')));
      await sync.setEnabled(true);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(_syncResultText(sync))));
    } else {
      await sync.setEnabled(false);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Sync disabled — local data kept.')),
      );
    }
  }

  // A read-only account/status dialog (Phase 5d, #294) — the identity + org a
  // device is on, plus the last pass. Maintainer-only; useful when bridging two
  // devices by hand (it surfaces the anon user id + org_id the manual
  // membership bridge needs).
  Future<void> _showSyncDetails() async {
    final sync = _sync;
    if (sync == null) return;
    // Through DeltaAuthService — the single seam onto Supabase auth — not the
    // raw client, so this stays correct if auth semantics change (email login).
    final auth = DeltaAuthService(widget.db);
    final userId = auth.currentUserId;
    final email = auth.currentUserEmail;
    final orgId = await widget.db.syncSetting(kSyncOrgId);
    if (!mounted) return;
    final lastSynced = sync.lastSyncedAt;
    final identity = userId == null ? 'no' : (email ?? 'anonymous');
    final rows = <(String, String)>[
      ('Enabled', sync.enabled ? 'yes' : 'no'),
      ('Signed in', identity),
      ('User id', userId ?? '—'),
      ('Org id', orgId ?? '—'),
      ('Last synced', lastSynced == null ? 'never' : '$lastSynced'),
      ('Last result', sync.lastResult?.toString() ?? '—'),
      if (sync.lastError != null) ('Last error', '${sync.lastError}'),
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sync details'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$label: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: value),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Email sign-in / sign-out (Auth slice 1, #310). Maintainer-only, behind the
  // delta gate. Email/password so two devices signing into the SAME account
  // share one org (the 2-device goal) with no SMTP and no deep-link plumbing —
  // works identically on Linux and Android. Signed in → offer sign-out;
  // otherwise email + password with Create-account / Sign-in. NB this starts a
  // fresh email session (its own org); it does NOT migrate anon local data onto
  // the account — use Export/Import for that until the linking slice (#311).
  Future<void> _showSyncAccount() async {
    final sync = _sync;
    if (sync == null) return;
    final auth = DeltaAuthService(widget.db);
    final messenger = ScaffoldMessenger.of(context);
    final emailCtrl = TextEditingController(text: auth.currentUserEmail ?? '');
    final passwordCtrl = TextEditingController();
    // Hoisted out of the builder so they survive rebuilds (setDialogState).
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Re-read on each rebuild so a completed sign-out flips the UI.
          final signedInEmail = auth.currentUserEmail;

          void update(void Function() fn) => setDialogState(fn);

          // Run an auth action, then (on success) close and report. Pop FIRST,
          // then — for a sign-in/create ([syncAfter]) — kick a pass so the org
          // resolves + local rows push. The pass is deferred to after the frame
          // so its controller notifications never rebuild the settings panel
          // while this dialog is being torn down (that ordering trips a
          // framework `_dependents` assertion). Sign-out passes syncAfter:false
          // — there's nothing to sync, and a no-account pass would skip anyway.
          Future<void> submit(
            Future<void> Function() action,
            String okMessage, {
            bool syncAfter = false,
          }) async {
            update(() {
              busy = true;
              error = null;
            });
            try {
              await action();
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              messenger.showSnackBar(SnackBar(content: Text(okMessage)));
              if (syncAfter && sync.enabled) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) sync.requestSync(SyncTrigger.foreground);
                });
              }
            } catch (e) {
              update(() {
                busy = false;
                error = '$e';
              });
            }
          }

          final children = <Widget>[];
          if (signedInEmail != null) {
            children.add(Text('Signed in as $signedInEmail.'));
          } else {
            children.add(
              const Text(
                'Sign in with an email + password to share sync across your '
                'devices — use the same account on each. Nothing is emailed.',
              ),
            );
            children.add(const SizedBox(height: 12));
            children.add(
              TextField(
                controller: emailCtrl,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@timedart.app',
                ),
              ),
            );
            children.add(const SizedBox(height: 12));
            children.add(
              TextField(
                controller: passwordCtrl,
                enabled: !busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            );
          }
          if (error != null) {
            children.add(const SizedBox(height: 12));
            children.add(
              Text(
                error!,
                style:
                    TextStyle(color: Theme.of(dialogContext).colorScheme.error),
              ),
            );
          }

          final actions = <Widget>[
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ];
          if (signedInEmail != null) {
            actions.add(
              FilledButton(
                onPressed: busy
                    ? null
                    : () => submit(
                          auth.signOut,
                          'Signed out — local data kept.',
                        ),
                child: const Text('Sign out'),
              ),
            );
          } else {
            final email = emailCtrl.text.trim();
            actions.add(
              TextButton(
                onPressed: busy
                    ? null
                    : () => submit(
                          () => auth.signUpWithPassword(
                            email: email,
                            password: passwordCtrl.text,
                          ),
                          'Account created — signed in as $email.',
                          syncAfter: true,
                        ),
                child: const Text('Create account'),
              ),
            );
            actions.add(
              FilledButton(
                onPressed: busy
                    ? null
                    : () => submit(
                          () => auth.signInWithPassword(
                            email: email,
                            password: passwordCtrl.text,
                          ),
                          'Signed in as $email.',
                          syncAfter: true,
                        ),
                child: const Text('Sign in'),
              ),
            );
          }

          return AlertDialog(
            title: const Text('Sync account'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
            actions: actions,
          );
        },
      ),
    );
    emailCtrl.dispose();
    passwordCtrl.dispose();
  }

  // Shared release dialog: the version + markdown notes, and a button that opens
  // the release page in the browser (Phase 1 hands the download off to the OS).
  Future<void> _showUpdateDialog(AppRelease release) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Update available — ${release.tag}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: SingleChildScrollView(
          child: MarkdownBody(
            data: release.notes.trim().isEmpty
                ? 'A new version of timedart is available.'
                : release.notes,
            styleSheet: appMarkdownStyleSheet(Theme.of(dialogContext)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            launchUrl(
              Uri.parse(release.url),
              mode: LaunchMode.externalApplication,
            );
          },
          child: const Text('Download'),
        ),
      ],
    ),
  );

  // App Settings home.
  void _openSettings() => _navigateTo(const _Settings());
  void _showSettingsHome() => _navigateTo(const _Settings());
  void _addTemplate() => _navigateTo(const _TemplateEditorDetail(null));
  void _editTemplate(InvoiceTemplate t, {bool startEditing = false}) =>
      _navigateTo(_TemplateEditorDetail(t, startEditing: startEditing));
  void _addProfile() => _navigateTo(const _ProfileEditorDetail(null));
  void _editProfile(InvoiceProfile p, {bool startEditing = false}) =>
      _navigateTo(_ProfileEditorDetail(p, startEditing: startEditing));

  // ── Narrow list-panel sheet (open/close + drag settle) ──────────────
  void _openPanel() {
    setState(() => _panelOpen = true);
    _sheetCtrl.animateTo(1, curve: Curves.easeOutCubic);
  }

  void _closePanel() {
    setState(() => _panelOpen = false);
    _sheetCtrl.animateBack(0, curve: Curves.easeOutCubic);
  }

  void _togglePanel() => _panelOpen ? _closePanel() : _openPanel();

  // Release after a handle drag: a decisive flick wins by direction; otherwise
  // snap to whichever end is nearer.
  void _settleSheet(double velocity) {
    final open = velocity.abs() > 400 ? velocity < 0 : _sheetCtrl.value >= 0.5;
    open ? _openPanel() : _closePanel();
  }

  @override
  void initState() {
    super.initState();
    // DB-backed timer: build with the db and recover any persisted running
    // session so it survives a restart (PRD #189, Phase 3). If a session comes
    // back bound to a project, select it so the tracker opens on the work in
    // progress (the tracker then reveals the active task itself).
    _timer = TimerController(widget.db);
    _timer.recover().then((_) {
      if (!mounted) return;
      final pid = _timer.boundProjectId;
      if (pid != null) setState(() => _selectedProjectId = pid);
    });
    // Start with the gate-resolved selection so the tracker paints content on
    // its first frame; if none was passed, fall back to the first project (or
    // leave it null → the tracker shows its "select a project" empty state).
    _selectedProjectId = widget.initialSelectedProjectId;
    widget.db.firstProjectId().then((id) {
      if (mounted && id != null) {
        setState(() => _selectedProjectId ??= id); // default only if unset
      }
    });
    widget.db.ensureInvoiceDefaults(); // seed timedart theme/profile/template

    // Delta-sync (Phase 5c triggers + 5d opt-in, #294): stand up the controller
    // and observe app lifecycle / timer-stop, but stay dormant until the
    // maintainer has opted in. Restoring `sync.delta.enabled == '1'` arms the
    // scheduler and kicks the first pass (sign-in + adoption). While off, every
    // trigger is a no-op. Maintainer-only — inert without the build gate.
    if (deltaSyncConfigured) {
      final sync = SyncController(widget.db);
      _sync = sync;
      WidgetsBinding.instance.addObserver(this);
      _timer.onEntryCommitted = () => sync.requestSync(SyncTrigger.timerStop);
      widget.db.syncSetting(kSyncEnabled).then((v) {
        if (mounted) sync.setEnabled(v == '1');
      });
    }

    // Notify (don't auto-install) if a newer release exists. Fire-and-forget,
    // non-blocking, silent on failure — never gates startup (Phase 1 update
    // check). Skipped on web, which is always the deployed latest.
    if (!kIsWeb) _autoCheckForUpdates();

    // Keep the selection honest when projects change: if the selected project is
    // deleted, fall back to the first remaining project (or none).
    _projectsSub = widget.db.watchProjects().listen((projects) {
      if (!mounted) return;
      final ids = projects.map((j) => j.id).toSet();
      final selected = _selectedProjectId;
      if (selected != null && !ids.contains(selected)) {
        setState(
          () => _selectedProjectId = projects.isNotEmpty
              ? projects.first.id
              : null,
        );
      }
    });
  }

  @override
  void dispose() {
    if (_sync != null) WidgetsBinding.instance.removeObserver(this);
    _sync?.dispose();
    _projectsSub?.cancel();
    _panelCursor.dispose();
    _settingsCursor.dispose();
    _trackerScope.dispose();
    _trackerCursor.dispose();
    _panelSearch.dispose();
    _settingsSearch.dispose();
    _sheetCtrl.dispose();
    _timer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sync on return-to-foreground so the other device's edits land promptly.
    // Silent (no snackbar) — the status line reflects it. Only registered as an
    // observer when sync is active, so `_sync` is non-null here.
    if (state == AppLifecycleState.resumed) {
      _sync?.requestSync(SyncTrigger.foreground);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget detailView = switch (_detail) {
      _Tracker() => TimerView(
        db: widget.db,
        projectId: _selectedProjectId,
        onInvoice: _invoiceProject,
        // Keyboard cursor for the entry list; only ever focused in the wide
        // layout (Tab / Ctrl-h / Ctrl-w h), inert in the drawer.
        cursorFocusNode: _trackerCursor,
        controller: _timer,
        onFocusTracker: _focusTracker,
        onFocusPanel: _focusPanel,
      ),
      _Invoice(:final project) => InvoiceView(
        db: widget.db,
        project: project,
        onDone: _showTracker,
      ),
      _Settings() => const SettingsHome(),
      _TemplateEditorDetail(:final template, :final startEditing) =>
        TemplateEditor(
          key: ValueKey(('template', template?.id)),
          db: widget.db,
          initial: template,
          startEditing: startEditing,
          onDone: _showSettingsHome,
          onSessionReady: (s) => _activeEditor = s,
        ),
      _ProfileEditorDetail(:final profile, :final startEditing) =>
        ProfileEditor(
          key: ValueKey(('profile', profile?.id)),
          db: widget.db,
          initial: profile,
          startEditing: startEditing,
          onDone: _showSettingsHome,
          onSessionReady: (s) => _activeEditor = s,
        ),
    };
    // Cross-fade between content-pane pages on a _detail change. PageTransitionSwitcher
    // fires only when its child's Key changes, so key by the page *type* — switching
    // between two templates keeps the same key here and is handled by the editor's own
    // ValueKey below, rather than fading between two editors.
    final animatedDetail = PageTransitionSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
        animation: primary,
        secondaryAnimation: secondary,
        fillColor: Colors.transparent, // no flash of canvasColor between pages
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey(_detail.runtimeType),
        child: detailView,
      ),
    );
    // Preview pages (settings + per-project invoice) keep the left edge aligned with
    // the page header (same inset as the centred content column) but stretch
    // right to the panel divider so the preview + controls use the extra width.
    // Other pages stay centred within ContentBody's reading width.
    // Wide layout: stretch pages left-align under the header logo — margin centres
    // a notional content column, +spaceMd matches the logo inset (keep in sync
    // with page_header.dart). Narrow (mobile) has no left-aligned header logo, so
    // match the tracker's plain spaceLg inset on all sides; the extra spaceMd
    // otherwise reads as too much horizontal padding.
    Widget buildContent({required bool wide}) => _stretchContent
        ? LayoutBuilder(
            builder: (context, c) {
              final margin = wide
                  ? ((c.maxWidth - AppTokens.maxContentWidth) / 2).clamp(
                      0.0,
                      double.infinity,
                    )
                  : 0.0;
              final left = wide
                  ? margin + AppTokens.spaceLg + AppTokens.spaceMd
                  : AppTokens.spaceLg;
              return Padding(
                // Narrow: trim the bottom inset — the bottom nav bar below
                // already separates content from the chrome (matches
                // content_body.dart; keep the two in sync).
                padding: EdgeInsets.fromLTRB(
                  left,
                  AppTokens.spaceLg,
                  AppTokens.spaceLg,
                  wide ? AppTokens.spaceLg : AppTokens.spaceMd,
                ),
                child: animatedDetail,
              );
            },
          )
        : ContentBody(child: animatedDetail);

    // In the narrow layout the panel lives in a drawer, so every action must
    // close the drawer first to reveal the content pane it just changed.
    // `before` runs that pop; in the wide layout it's null (panel is persistent).
    Widget panel({
      VoidCallback? before,
      bool keyboardNav = false,
      bool showFooter = true,
    }) {
      void run(VoidCallback action) {
        before?.call();
        action();
      }

      // In Settings mode the right column is the settings panel instead of the
      // client/project tree; the content pane shows the matching preview.
      if (_inSettings) {
        final detail = _detail;
        return SettingsPanel(
          db: widget.db,
          selectedTemplateId: detail is _TemplateEditorDetail
              ? detail.template?.id
              : null,
          selectedProfileId: detail is _ProfileEditorDetail
              ? detail.profile?.id
              : null,
          onBack: () => run(_showTracker),
          onAddTemplate: () => run(_addTemplate),
          onEditTemplate: (t, {startEditing = false}) =>
              run(() => _editTemplate(t, startEditing: startEditing)),
          onAddProfile: () => run(_addProfile),
          onEditProfile: (p, {startEditing = false}) =>
              run(() => _editProfile(p, startEditing: startEditing)),
          onRerunOnboarding: widget.onRerunOnboarding,
          onExportData: () async => run(_exportData),
          onImportData: () async => run(_importData),
          onCheckForUpdates: kIsWeb ? null : () async => run(_checkForUpdates),
          // Maintainer-only "Sync now" — Phase 5a delta-sync (#294). Wired only
          // in an ENABLE_DELTA_SYNC build with keys; released builds omit it.
          onSyncNow: deltaSyncConfigured ? () async => run(_syncNow) : null,
          // The 5c controller drives the Sync-now row's status suffix (idle /
          // syncing / synced Xm ago / offline) and the 5d enable/disable state.
          // Null in released builds.
          syncController: _sync,
          // Maintainer-only delta opt-in + details (Phase 5d, #294). Wired only
          // in an ENABLE_DELTA_SYNC build; released builds omit both rows.
          onToggleDeltaSync: deltaSyncConfigured
              ? () async => run(_toggleDeltaSync)
              : null,
          onSyncDetails: deltaSyncConfigured
              ? () async => run(_showSyncDetails)
              : null,
          // Maintainer-only email sign-in / sign-out (Auth slice 1, #310).
          onSyncAccount: deltaSyncConfigured
              ? () async => run(_showSyncAccount)
              : null,
          // Same footer as the normal panel; Shortcuts only where keys are live.
          onShowHelp: keyboardNav ? () => showShortcutsHelp(context) : null,
          onOpenSettings: () => run(_openSettings),
          onOpenTracker: () => run(_showTracker),
          onFocusTracker: keyboardNav ? _focusTracker : null,
          onFocusPanel: keyboardNav ? _focusPanel : null,
          settingsActive: true,
          showFooter: showFooter,
          autofocus: keyboardNav,
          // Keyboard nav wired only where the panel is persistent (wide) —
          // mirrors SidePanel below, so Tab/Ctrl-h/Ctrl-l pane-switching can
          // actually reach this panel's row cursor instead of a focus node
          // nothing is listening on.
          cursorFocusNode: keyboardNav ? _settingsCursor : null,
          searchFocusNode: keyboardNav ? _settingsSearch : null,
        );
      }

      return SidePanel(
        db: widget.db,
        selectedProjectId: _selectedProjectId,
        onSelect: (id) => run(() => _selectProject(id)),
        onEditProject: (j) => run(() => _editProject(j)),
        onAddProject: (cid) => run(() => _addProject(cid)),
        onEditClient: (c) => run(() => _editClient(c)),
        onAddClient: () => run(_addClient),
        // Keyboard nav is wired only where the panel is persistent (wide).
        cursorFocusNode: keyboardNav ? _panelCursor : null,
        searchFocusNode: keyboardNav ? _panelSearch : null,
        onFocusTracker: keyboardNav ? _focusTracker : null,
        onFocusPanel: keyboardNav ? _focusPanel : null,
        // `?` while the panel is focused: the panel consumes `/`-family keys, so
        // it routes the help request back up rather than letting it bubble.
        onShowHelp: keyboardNav ? () => showShortcutsHelp(context) : null,
        onOpenSettings: () => run(_openSettings),
        onOpenTracker: () => run(_showTracker),
        settingsActive: false,
        showFooter: showFooter,
        autofocus: keyboardNav,
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= AppTokens.breakpointMd) {
          return Scaffold(
            // Observes bubbled key events for pane-switching without stealing
            // primary focus from the pane widgets themselves.
            body: Focus(
              onKeyEvent: _onShellKey,
              canRequestFocus: false,
              skipTraversal: true,
              child: Row(
                children: [
                  // Logo bar sits atop the content pane, level with the panel's
                  // search field; the detail view fills the rest below it.
                  Expanded(
                    child: FocusScope(
                      node: _trackerScope,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Shortcuts + Settings live here (right of the bar,
                          // left of the panel divider), not in the panel footer.
                          PageHeader(
                            alignLogoStart: _wideContentPage,
                            onShowHelp: () => showShortcutsHelp(context),
                            onOpenSettings: _openSettings,
                            onOpenTracker: _showTracker,
                            settingsActive: _inSettings,
                          ),
                          Expanded(child: buildContent(wide: true)),
                        ],
                      ),
                    ),
                  ),

                  const VerticalDivider(
                    width: AppTokens.strokeThick,
                    color: AppTokens.colorBorder,
                  ),

                  // Footer suppressed: Shortcuts/Settings are in the header now.
                  SizedBox(
                    width: 320,
                    child: ClipRect(
                      child: PageTransitionSwitcher(
                        duration: const Duration(milliseconds: 300),
                        reverse: true,
                        transitionBuilder: (child, primary, secondary) =>
                            SharedAxisTransition(
                              animation: primary,
                              secondaryAnimation: secondary,
                              transitionType:
                                  SharedAxisTransitionType.horizontal,
                              fillColor: Colors.transparent,
                              child: child,
                            ),
                        child: KeyedSubtree(
                          key: ValueKey(_inSettings),
                          child: panel(keyboardNav: true, showFooter: false),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        // One mobile bottom-bar tab (icon over label), tinted by active state.
        // `icon` is built with the resolved foreground colour.
        Widget mobileTab({
          required bool active,
          required String label,
          required Widget Function(Color) icon,
          required VoidCallback onTap,
        }) {
          final fg = active ? scheme.primary : scheme.onSurfaceVariant;
          // Match the centre button's exact height (iconMd + spaceSm top/bottom
          // padding). All three are centred in the bar, so pinning icon→top and
          // label→bottom over this height lines the tab up with the button.
          const tabHeight = AppTokens.iconMd + AppTokens.spaceSm * 2;
          return InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 76,
              height: tabHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  icon(fg),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          // Same logo-bar style as the wide layout, but full-width with no
          // rounding; a gap above matches the search field's gap in the drawer.
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            // Flush to the top: only the SafeArea inset (status bar/notch) sits
            // above the logo bar — no extra margin, to reclaim vertical space.
            child: SafeArea(
              bottom: false,
              // The app is single-theme dark, and the header uses a custom
              // container (not an AppBar), so nothing else sets the overlay
              // style. Pin light status-bar icons for contrast against the dark
              // header, and transparent bars for the edge-to-edge look. Static
              // because there's no light theme to switch between.
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  color: scheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                    vertical: AppTokens.spaceXs,
                  ),
                  // Logo centred now the hamburger is gone (nav is the bottom bar).
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/logo/timedart_logo_horizontal.svg',
                      height: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bottom bar stays present while the panel is open: the centre button
          // toggles the project/settings list as an overlay above the content,
          // and the Tracker/Settings tabs remain tappable throughout.
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: AppTokens.strokeThin,
                color: AppTokens.colorBorder,
              ),
              SafeArea(
                top: false,
                child: Material(
                  color: scheme.surface,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        mobileTab(
                          active: !_inSettings,
                          label: 'Tracker',
                          // Nudged down by half the icon-size gap (iconLg−iconMd)
                          // so its centre lines up with the larger Settings gear.
                          icon: (c) => Padding(
                            padding: const EdgeInsets.only(
                              top: AppTokens.space4xs,
                            ),
                            child: SvgPicture.asset(
                              'assets/logo/timedart_symbol.svg',
                              height: AppTokens.iconMd,
                              colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
                            ),
                          ),
                          onTap: _showTracker,
                        ),
                        // Pronounced centre button — opens/closes the list panel.
                        // Styled like the app's primary button: muted accent-dim
                        // fill + accent text at rest (drawer closed), flipping to
                        // the bright fill when open.
                        Material(
                          color: _panelOpen
                              ? AppTokens.colorAccentText
                              : AppTokens.colorAccentDim,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusButton,
                            ),
                            side: BorderSide(
                              color: AppTokens.colorBrandPrimary.withValues(
                                alpha: 0.30,
                              ),
                              width: AppTokens.strokeThin,
                            ),
                          ),
                          child: InkWell(
                            onTap: _togglePanel,
                            child: Padding(
                              padding: const EdgeInsets.all(AppTokens.spaceSm),
                              child: Icon(
                                _panelOpen ? Icons.close : Icons.menu,
                                color: _panelOpen
                                    ? AppTokens.colorOnAccent
                                    : AppTokens.colorAccentText,
                                size: AppTokens.iconMd,
                              ),
                            ),
                          ),
                        ),
                        mobileTab(
                          active: _inSettings,
                          label: 'Settings',
                          // iconLg (not iconMd) so the Material gear's built-in
                          // glyph padding reads the same visual size as the
                          // edge-to-edge Tracker SVG at iconMd.
                          icon: (c) => Icon(
                            Icons.settings,
                            size: AppTokens.iconLg,
                            color: c,
                          ),
                          onTap: _openSettings,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(child: buildContent(wide: false)),
              // Scrim over the content (the bottom bar sits outside this Stack,
              // so it stays live). Fades with the sheet; ignores taps when closed.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_panelOpen,
                  child: FadeTransition(
                    opacity: _sheetCtrl, // fades in step with the sheet's drag
                    child: GestureDetector(
                      onTap: _closePanel,
                      child: const ColoredBox(color: Colors.black54),
                    ),
                  ),
                ),
              ),
              // Project/settings list as a drawer-like sheet that slides up from
              // the bottom. A real Scaffold endDrawer would cover the bottom bar;
              // this body overlay keeps the bar live and toggleable. The bottom
              // Padding lifts the sheet clear of the on-screen keyboard when a
              // field inside it (e.g. the search box) is focused.
              Positioned.fill(
                // The closed sheet is hidden only by SlideTransition's
                // paint-time translation (Offset(0,1)), which doesn't change
                // layout — so the Stack sees no overflow and never clips it. In
                // edge-to-edge that translated sheet paints through the nav
                // bar's transparent bottom safe-area strip. ClipRect confines it
                // to the body bounds; the open sheet is within bounds, untouched.
                child: ClipRect(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: LayoutBuilder(
                      builder: (context, bodyC) {
                        // Sheet height in pixels — the divisor that maps a drag in
                        // logical pixels to the controller's 0..1 range for 1:1
                        // finger tracking.
                        final sheetHeight = bodyC.maxHeight * 0.85;
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: IgnorePointer(
                            ignoring: !_panelOpen,
                            child: SlideTransition(
                              position: _sheetOffset,
                              child: FractionallySizedBox(
                                heightFactor: 0.85,
                                child: Material(
                                  color: scheme.surface,
                                  clipBehavior: Clip.antiAlias,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(AppTokens.radiusLg),
                                    ),
                                    side: BorderSide(
                                      color: AppTokens.colorBorder,
                                      width: AppTokens.strokeThin,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      // Grab handle — drag it to follow the finger,
                                      // release to fling/snap open or closed.
                                      GestureDetector(
                                        behavior: HitTestBehavior
                                            .opaque, // catch drags on the whole strip, not just the 4px bar
                                        onVerticalDragUpdate: (d) =>
                                            _sheetCtrl.value -=
                                                d.delta.dy / sheetHeight,
                                        onVerticalDragEnd: (d) => _settleSheet(
                                          d.primaryVelocity ?? 0,
                                        ),
                                        child: const SheetGrabHandle(),
                                      ),
                                      Expanded(
                                        child: panel(
                                          before: _closePanel,
                                          showFooter: false,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
