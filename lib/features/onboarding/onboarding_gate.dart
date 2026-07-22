import 'package:flutter/material.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/sync_config.dart';
import 'package:timedart/features/onboarding/onboarding_controller.dart';
import 'package:timedart/features/onboarding/onboarding_flow.dart';
import 'package:timedart/features/onboarding/onboarding_intro.dart';
import 'package:timedart/features/shell/adaptive_shell.dart';

// The app's root gate (PRD #133, phases c/e). Replaces main.dart's direct
// [AdaptiveShell] mount: it plays the brief startup intro, seeds the defaults,
// then decides between the first-run onboarding flow and the tracker based on
// the persisted onboarding-complete flag. Also owns "Re-run setup" — the
// Settings action that replays onboarding (and doubles as the dev/test reset).
class RootGate extends StatefulWidget {
  const RootGate({super.key, required this.db});
  final AppDatabase db;

  @override
  State<RootGate> createState() => _RootGateState();
}

enum _Mode { intro, onboarding, shell }

class _RootGateState extends State<RootGate> {
  _Mode _mode = _Mode.intro;

  // The intro plays while bootstrap runs; we advance once BOTH are done. Null
  // until the flag resolves.
  bool _introDone = false;
  bool? _onboardingComplete;

  // Resolved during bootstrap and handed to the shell so the tracker opens on a
  // project without an empty first frame.
  String? _defaultProjectId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // Seed defaults first (so the default profile exists before the wizard can
  // edit it), then resolve the flag and try to advance.
  Future<void> _bootstrap() async {
    try {
      await widget.db.ensureInvoiceDefaults();
      // Seed the first-run example data (once, empty DB only), then open on its
      // first project — or none, if a returning user has cleared everything.
      // Skipped when sync is on: writing example data into the synced store
      // pollutes the org and stalls startup against the live PowerSync
      // connection. Real seeding is Phase 4d (seed-from-snapshot on enable).
      if (!syncEnabled) {
        await widget.db.seedFirstRunExampleData();
      }
      _defaultProjectId = await widget.db.firstProjectId();
      // Mint the stable per-install id now (idempotent) so existing installs
      // acquire one before the optional sync layer needs it (PRD #189, Phase 4).
      await widget.db.installId();
      _onboardingComplete = await widget.db.isOnboardingComplete();
    } catch (e, st) {
      // Sync is additive — a hiccup on the sync-backed connection must never
      // strand the intro. Fall back to onboarding so the app still opens.
      debugPrint('RootGate bootstrap error: $e\n$st');
      _onboardingComplete = false;
    }
    if (!mounted) return;
    _advanceFromIntro();
  }

  // Leave the intro only when it has finished playing AND the flag is known, so
  // neither a slow DB read nor a fast tap-skip can strand the user.
  void _advanceFromIntro() {
    if (!_introDone || _onboardingComplete == null) return;
    setState(
      () => _mode = _onboardingComplete! ? _Mode.shell : _Mode.onboarding,
    );
  }

  void _onIntroFinished() {
    _introDone = true;
    _advanceFromIntro();
  }

  Future<void> _finish(OnboardingInputs inputs) async {
    await applyOnboarding(widget.db, inputs);
    if (mounted) setState(() => _mode = _Mode.shell);
  }

  // Settings → "Re-run setup": clear the flag and replay the whole first-run
  // experience — the intro animation, then a fresh wizard. Resetting
  // _introDone routes back through the intro (the flag is already known false,
  // so it lands on onboarding once the intro finishes).
  Future<void> _rerun() async {
    await widget.db.setOnboardingComplete(false);
    if (!mounted) return;
    setState(() {
      _onboardingComplete = false;
      _introDone = false;
      _mode = _Mode.intro;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (_mode) {
      _Mode.intro => OnboardingIntro(onFinish: _onIntroFinished),
      _Mode.onboarding => OnboardingFlow(onDone: _finish),
      // The shell settles in with a subtle scale on top of the cross-fade, so
      // arriving at the tracker (from the intro or from finishing onboarding)
      // eases in rather than snapping.
      _Mode.shell => _ShellEntrance(
        child: AdaptiveShell(
          db: widget.db,
          onRerunOnboarding: _rerun,
          initialSelectedProjectId: _defaultProjectId,
        ),
      ),
    };
    // Cross-fade between phases. Because the intro mirrors the Welcome step's
    // logo geometry, a plain fade makes the logo read as staying put while the
    // welcome copy fades in around it.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: KeyedSubtree(key: ValueKey(_mode), child: child),
    );
  }
}

// Eases the shell in on first mount: a gentle scale-up settle. The fade is
// supplied by the gate's [AnimatedSwitcher]; this adds only the motion. Runs
// once — later shell rebuilds keep the completed (identity) transform.
class _ShellEntrance extends StatefulWidget {
  const _ShellEntrance({required this.child});
  final Widget child;
  @override
  State<_ShellEntrance> createState() => _ShellEntranceState();
}

class _ShellEntranceState extends State<_ShellEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();
  late final Animation<double> _scale = Tween(
    begin: 0.97,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
