import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:timedart/constants/tokens.dart';

// The startup intro (PRD #133, phase e): a brief (~1s) branded animation of the
// timedart mark shown at every launch, ahead of the root gate's route decision.
// The logo fades and scales up, holds, then calls [onFinish]. Tapping anywhere
// skips straight to [onFinish] — it must never block getting to work.
//
// The frame deliberately MIRRORS the wizard's Welcome step (same reserved
// top-bar height, same centred 640 column, same logo size, with the heading /
// byline / button present but invisible) so the logo lands in the exact same
// spot. Combined with the root gate's cross-fade, the logo appears to stay put
// while the welcome copy fades in around it. Keep in sync with
// OnboardingFlow._welcome.
class OnboardingIntro extends StatefulWidget {
  const OnboardingIntro({super.key, required this.onFinish});
  final VoidCallback onFinish;

  // The wizard's top bar is spaceMd of top padding over a tap-target-tall row.
  static const double _topBarHeight =
      AppTokens.spaceMd + kMinInteractiveDimension;
  static const double _maxWidth = 640;

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
    curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
  );
  late final Animation<double> _scale = Tween(begin: 0.9, end: 1.0).animate(
    CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
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
    final narrow = MediaQuery.sizeOf(context).width < AppTokens.breakpointMd;
    final theme = Theme.of(context);

    // Invisible placeholders matching the welcome copy so the logo's position
    // is identical to the wizard's Welcome step.
    Widget ghost(Widget child) =>
        Opacity(opacity: 0, child: IgnorePointer(child: child));

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: OnboardingIntro._topBarHeight),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceXl,
                      vertical: AppTokens.spaceLg,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: OnboardingIntro._maxWidth,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FadeTransition(
                            opacity: _fade,
                            child: ScaleTransition(
                              scale: _scale,
                              child: SvgPicture.asset(
                                'assets/logo/timedart_logo_stacked.svg',
                                height: narrow ? 140 : 240,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppTokens.spaceXl),
                          ghost(
                            Text(
                              'Welcome',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: AppTokens.spaceMd),
                          ghost(
                            Text(
                              'Track time against your projects and send '
                              'invoices ',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          ghost(
                            Text(
                              'tailored to your brand.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(height: AppTokens.space2xl),
                          ghost(
                            FilledButton(
                              onPressed: null,
                              child: const Text('Get started'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
