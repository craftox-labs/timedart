import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:time_tracker/constants/tokens.dart';

// The startup intro (PRD #133, phase e): a brief (~1s) branded animation of the
// timedart mark shown at every launch, ahead of the root gate's route decision.
// The logo fades and scales up, holds briefly, then calls [onFinish]. Tapping
// anywhere skips straight to [onFinish] — it must never block getting to work.
class OnboardingIntro extends StatefulWidget {
  const OnboardingIntro({super.key, required this.onFinish});
  final VoidCallback onFinish;

  @override
  State<OnboardingIntro> createState() => _OnboardingIntroState();
}

class _OnboardingIntroState extends State<OnboardingIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    // Fade in over the first ~60%, then hold.
    curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
  );
  late final Animation<double> _scale = Tween(begin: 0.85, end: 1.0).animate(
    CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
    ),
  );

  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  }

  // Fire onFinish at most once (animation end or a tap-to-skip).
  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinish();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: SvgPicture.asset(
                'assets/logo/timedart_logo_stacked.svg',
                height: 200,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
