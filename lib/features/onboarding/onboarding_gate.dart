import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/onboarding/onboarding_controller.dart';
import 'package:time_tracker/features/onboarding/onboarding_flow.dart';
import 'package:time_tracker/features/onboarding/onboarding_intro.dart';
import 'package:time_tracker/features/shell/adaptive_shell.dart';

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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // Seed defaults first (so the default profile exists before the wizard can
  // edit it), then resolve the flag and try to advance.
  Future<void> _bootstrap() async {
    await widget.db.ensureDefaultProject();
    await widget.db.ensureInvoiceDefaults();
    final complete = await widget.db.isOnboardingComplete();
    if (!mounted) return;
    _onboardingComplete = complete;
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

  // Settings → "Re-run setup": clear the flag and replay the wizard in place
  // (a fresh OnboardingFlow, so its step machine starts over). No intro replay.
  Future<void> _rerun() async {
    await widget.db.setOnboardingComplete(false);
    if (mounted) setState(() => _mode = _Mode.onboarding);
  }

  @override
  Widget build(BuildContext context) => switch (_mode) {
    _Mode.intro => OnboardingIntro(onFinish: _onIntroFinished),
    _Mode.onboarding => OnboardingFlow(onDone: _finish),
    _Mode.shell => AdaptiveShell(db: widget.db, onRerunOnboarding: _rerun),
  };
}
