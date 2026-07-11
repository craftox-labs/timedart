import 'dart:async';
import 'dart:typed_data';

import 'package:animations/animations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/invoices/editor_common.dart';
import 'package:timedart/features/invoices/invoice_region.dart';
import 'package:timedart/features/onboarding/onboarding_controller.dart';
import 'package:timedart/features/onboarding/onboarding_machine.dart';

// The first-run onboarding wizard (PRD #133, phase d). A full-screen stepped
// flow driven by [OnboardingMachine]: Welcome → How it works → Your business →
// Your region → Done. Orientation precedes any input; every input step is
// skippable (leave the fields blank and continue, or "Skip setup" entirely) and
// whatever is captured is applied to the seeded default profile by the root
// gate via [applyOnboarding].
//
// The "How it works" step ([_HowItWorks]) auto-cycles through the
// Client → Project → Task → Timer → Invoice sequence with a sliding panel and
// tappable flow cards (#137); bespoke per-stage illustrations remain to come.
// The startup intro animation is phase (e), ahead of the gate.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});

  /// Called once when the flow finishes (last step or "Skip setup"), carrying
  /// whatever was captured. Blank fields stay null → seeded defaults kept.
  final ValueChanged<OnboardingInputs> onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow>
    with SingleTickerProviderStateMixin {
  final _machine = OnboardingMachine();
  final _businessName = TextEditingController();
  final _email = TextEditingController();
  Uint8List? _logo;
  String? _logoMime;
  InvoiceRegion? _region;

  static const double _maxWidth = 640;

  // One-shot entrance: as the intro cross-fades into this Welcome screen (the
  // logo staying put), the top bar slides down and everything below the logo
  // slides up into place. Runs once at mount, so it only affects the first
  // Welcome frame; later steps use the page switcher.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    _businessName.dispose();
    _email.dispose();
    super.dispose();
  }

  // Slide + settle from [begin] (a fraction of the child's size), driven by the
  // entrance controller. At rest (post-animation) it's the identity, so wrapping
  // shared chrome is safe on later steps. The fade comes from the gate's
  // cross-fade of the whole screen.
  Widget _entranceSlide(Widget child, Offset begin) => SlideTransition(
    position: Tween(
      begin: begin,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic)),
    child: child,
  );

  OnboardingInputs get _captured => OnboardingInputs(
    businessName: _businessName.text,
    email: _email.text,
    logo: _logo,
    logoMime: _logoMime,
    region: _region,
  );

  // Any machine transition funnels through here so completion fires onDone
  // exactly once (the machine latches isComplete).
  void _apply(void Function() transition) {
    setState(transition);
    if (_machine.isComplete) widget.onDone(_captured);
  }

  Future<void> _pickLogo() async {
    const group = XTypeGroup(
      label: 'Image',
      extensions: ['png', 'jpg', 'jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    setState(() {
      _logo = bytes;
      _logoMime = name.endsWith('.png') ? 'image/png' : 'image/jpeg';
    });
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < AppTokens.breakpointMd;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar slides down as the intro resolves into Welcome.
            _entranceSlide(_topBar(), const Offset(0, -1)),
            Expanded(
              child: PageTransitionSwitcher(
                transitionBuilder: (child, primary, secondary) =>
                    FadeThroughTransition(
                      animation: primary,
                      secondaryAnimation: secondary,
                      fillColor: Colors.transparent,
                      child: child,
                    ),
                child: KeyedSubtree(
                  key: ValueKey(_machine.current),
                  child: _stepScaffold(_machine.current, narrow),
                ),
              ),
            ),
            if (!_machine.isFirst) _bottomNav(),
          ],
        ),
      ),
    );
  }

  // Wraps a step body in the shared scroll-centred column: vertically centred,
  // scrollable when it outgrows a short window, capped to [_maxWidth].
  Widget _scrollCenter(Widget child) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceXl,
        vertical: AppTokens.spaceLg,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: child,
      ),
    ),
  );

  // Places each step in the body area. Most steps are scroll-centred; the
  // how-it-works diagram instead fills the height (title top, panel grows,
  // flow cards near the bottom) so it uses the whole screen rather than
  // floating a small box in a sea of empty space.
  Widget _stepScaffold(OnboardingStep step, bool narrow) => switch (step) {
    OnboardingStep.howItWorks => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceXl,
        vertical: AppTokens.spaceLg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: _HowItWorks(narrow: narrow),
        ),
      ),
    ),
    // Welcome's primary sits right below its byline (entrance-animated); every
    // other step uses the fixed bottom nav so its buttons land at a consistent
    // height across screens.
    OnboardingStep.welcome => _scrollCenter(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _welcome(narrow),
          const SizedBox(height: AppTokens.space2xl),
          _entranceSlide(Center(child: _primaryButton()), const Offset(0, 1)),
        ],
      ),
    ),
    OnboardingStep.business => _scrollCenter(_business()),
    OnboardingStep.region => _scrollCenter(_region_()),
    OnboardingStep.done => _scrollCenter(_done()),
  };

  // ── Chrome ────────────────────────────────────────────────────────────────

  // Full-width top bar: progress dots at the left edge, Skip at the right.
  Widget _topBar() {
    final showSkipAll =
        !_machine.isLast; // no "skip" on the closing Done screen
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceXl,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        0,
      ),
      // Fixed height (a button's tap target) so the dots stay at the same
      // vertical position even on the final step, which drops the Skip button.
      child: SizedBox(
        height: kMinInteractiveDimension,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ProgressDots(count: _machine.steps.length, index: _machine.index),
            const Spacer(),
            if (showSkipAll)
              TextButton(
                onPressed: () => _apply(_machine.skipAll),
                style: TextButton.styleFrom(shape: _buttonShape),
                child: const Text('Skip setup'),
              ),
          ],
        ),
      ),
    );
  }

  // Fixed bottom nav (steps 2..5): Back on the left, primary on the right,
  // aligned to the content column so the actions line up with the body above.
  Widget _bottomNav() => Padding(
    padding: const EdgeInsets.all(AppTokens.space2xl),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Row(
          children: [
            TextButton(
              onPressed: () => _apply(_machine.back),
              style: TextButton.styleFrom(
                shape: _buttonShape,
                minimumSize: _navButtonSize,
                side: const BorderSide(color: AppTokens.colorBorder),
              ),
              child: const Text('Back'),
            ),
            const Spacer(),
            _primaryButton(),
          ],
        ),
      ),
    ),
  );

  Widget _primaryButton() {
    final label = switch (_machine.current) {
      OnboardingStep.welcome => 'Get started',
      OnboardingStep.done => 'Go to tracker',
      _ => 'Next',
    };
    return FilledButton(
      onPressed: () => _apply(_machine.next),
      // Match Back's footprint so the two nav buttons read as a pair.
      style: FilledButton.styleFrom(
        shape: _buttonShape,
        minimumSize: _navButtonSize,
      ),
      child: Text(label),
    );
  }

  static final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
  );

  static const _navButtonSize = Size(112, 48);

  // ── Step bodies ─────────────────────────────────────────────────────────

  Widget _welcome(bool narrow) => _CenteredStep(
    children: [
      // The logo stays put across the intro→welcome cross-fade (its anchor);
      // only the copy below it slides up.
      SvgPicture.asset(
        'assets/logo/timedart_logo_stacked.svg',
        height: narrow ? 140 : 240,
      ),
      const SizedBox(height: AppTokens.spaceXl),
      _entranceSlide(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _title('Welcome'),
            const SizedBox(height: AppTokens.spaceMd),
            _body('Track time against your projects and send invoices '),
            _body('tailored to your brand.'),
          ],
        ),
        const Offset(0, 1),
      ),
    ],
  );

  Widget _business() => _FormStep(
    title: 'Your business',
    hint: 'This brands your invoices. You can change it later in Settings.',
    children: [
      _logoField(),
      const SizedBox(height: AppTokens.spaceMd),
      EditorTextField(
        controller: _businessName,
        label: 'Business name',
        persistentLabel: true,
      ),
      const SizedBox(height: AppTokens.spaceMd),
      EditorTextField(
        controller: _email,
        label: 'Email',
        persistentLabel: true,
      ),
    ],
  );

  Widget _region_() => _FormStep(
    title: 'Your region',
    hint:
        'Sets your currency and tax label automatically. Change it later in '
        'Settings.',
    children: [
      EditorDropdown<InvoiceRegion>(
        label: 'Region',
        value: _region,
        items: [
          for (final r in InvoiceRegion.values)
            DropdownMenuItem(value: r, child: Text(r.label)),
        ],
        onChanged: (v) => setState(() => _region = v),
      ),
      if (_region != null) ...[
        const SizedBox(height: AppTokens.spaceSm),
        _body(_regionCaption(_region!)),
      ],
    ],
  );

  Widget _done() => _CenteredStep(
    children: [
      // Material Symbols (variable font, weight 200) to match the how-it-works
      // flow icons rather than the stock Material tick.
      Icon(
        Symbols.check_circle,
        size: 240,
        weight: 200,
        opticalSize: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: AppTokens.spaceLg),
      _title('You\'re all set'),
      const SizedBox(height: AppTokens.spaceMd),
      _body(
        'Create your first client and project in the tracker to get going.',
      ),
      const SizedBox(height: AppTokens.spaceXs),
      _body('Visit settings at anytime to add/edit details.'),
    ],
  );

  // ── Small pieces ──────────────────────────────────────────────────────────

  Widget _logoField() {
    final t = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 72,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            border: Border.all(color: AppTokens.colorBorder),
          ),
          child: _logo == null
              ? Icon(
                  Icons.image_outlined,
                  size: AppTokens.iconSm,
                  color: t.colorScheme.onSurfaceVariant,
                )
              : Padding(
                  padding: const EdgeInsets.all(AppTokens.space3xs),
                  child: Image.memory(_logo!, fit: BoxFit.contain),
                ),
        ),
        const SizedBox(width: AppTokens.spaceXs),
        TextButton(onPressed: _pickLogo, child: const Text('Logo…')),
        if (_logo != null)
          IconButton(
            icon: const Icon(Icons.close, size: AppTokens.iconSm),
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove logo',
            onPressed: () => setState(() {
              _logo = null;
              _logoMime = null;
            }),
          ),
      ],
    );
  }

  String _regionCaption(InvoiceRegion r) {
    final parts = <String>[
      if (r.defaultCurrency != null) 'Currency: ${r.defaultCurrency}',
      r.defaultTaxLabel != null ? 'Tax: ${r.defaultTaxLabel}' : 'No sales tax',
    ];
    return parts.join('   ·   ');
  }

  Widget _title(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.headlineSmall,
  );

  Widget _body(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodyMedium,
  );
}

/// A vertically-centred step (orientation screens): a min-height column.
class _CenteredStep extends StatelessWidget {
  const _CenteredStep({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    ),
  );
}

/// An input step: left-aligned title + hint over a stretched field column,
/// scrollable so it survives short/narrow windows.
class _FormStep extends StatelessWidget {
  const _FormStep({
    required this.title,
    required this.hint,
    required this.children,
  });
  final String title;
  final String hint;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: t.textTheme.headlineSmall?.copyWith(
            color: t.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppTokens.space2xs),
        Text(
          hint,
          style: t.textTheme.bodySmall?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        ...children,
      ],
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.count, required this.index});
  final int count;
  final int index;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(right: AppTokens.space2xs),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index
                    ? t.colorScheme.primary
                    : AppTokens.colorBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}

/// The "How timedart works" step: a panel that cycles through the five stages
/// (Client → Project → Task → Timer → Invoice) — auto-advancing on a timer and
/// looping — over a row of flow cards. The current stage's card is highlighted;
/// tapping any card jumps to it and restarts the dwell timer. The panel slides
/// horizontally between stages (direction follows forward/backward moves).
class _HowItWorks extends StatefulWidget {
  const _HowItWorks({required this.narrow});
  final bool narrow;

  @override
  State<_HowItWorks> createState() => _HowItWorksState();
}

class _HowItWorksState extends State<_HowItWorks> {
  // (badge icon, card label, panel explanation, hero duo-SVG) per stage. The
  // hero uses the custom two-tone SVG; the step badges keep Material Symbols.
  static const _stages = <(IconData, String, String, String)>[
    (
      Symbols.face,
      'Client',
      'Add the people or companies you work for.',
      'assets/icons/client-duo.svg',
    ),
    (
      Symbols.file_present,
      'Project',
      'Group work under a client as a project.',
      'assets/icons/project-duo.svg',
    ),
    (
      Symbols.task,
      'Task',
      'Break a project into tasks you can track.',
      'assets/icons/task-duo.svg',
    ),
    (
      Symbols.hourglass_bottom,
      'Timer',
      'Clock time against a task as you work.',
      'assets/icons/time-duo.svg',
    ),
    (
      Symbols.diagnosis,
      'Invoice',
      'Turn tracked hours into a branded invoice.',
      'assets/icons/invoice-duo.svg',
    ),
  ];
  static const _dwell = Duration(seconds: 4);

  int _index = 0;
  bool _forward = true; // slide direction for the next panel transition
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_dwell, (_) {
      setState(() {
        _forward = true;
        _index = (_index + 1) % _stages.length;
      });
    });
  }

  // Tapping a card jumps there and restarts the dwell so the chosen stage gets
  // a full interval before auto-advance resumes.
  void _jump(int i) {
    if (i == _index) return;
    setState(() {
      _forward = i > _index;
      _index = i;
    });
    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How timedart works',
          textAlign: TextAlign.center,
          style: t.textTheme.headlineSmall?.copyWith(
            color: t.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        Expanded(child: _panel(t)),
        const SizedBox(height: AppTokens.spaceLg),
        _cards(),
      ],
    );
  }

  Widget _panel(ThemeData t) {
    final (_, _, copy, asset) = _stages[_index];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 350),
        reverse: !_forward,
        transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
          animation: primary,
          secondaryAnimation: secondary,
          transitionType: SharedAxisTransitionType.horizontal,
          fillColor: Colors.transparent,
          child: child,
        ),
        child: Column(
          key: ValueKey(_index),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  // Fill the shorter side of the available space, capped so the
                  // hero doesn't get oversized — smaller on mobile so it doesn't
                  // dominate a narrow window. Colours are baked into the two-tone
                  // SVG, so no colorFilter here.
                  final maxHero = widget.narrow ? 240.0 : 440.0;
                  final size = c.biggest.shortestSide.clamp(0.0, maxHero);
                  return Center(
                    child: SvgPicture.asset(
                      asset,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            Text(
              copy,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyLarge?.copyWith(
                color: t.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cards() {
    // Mobile: compact cards + tighter arrows so the whole sequence stays on one
    // line. Either way the row is scaled down to fit if it would still overflow.
    final compact = widget.narrow;
    final children = <Widget>[];
    for (var i = 0; i < _stages.length; i++) {
      if (i > 0) children.add(_FlowArrow(compact: compact));
      final (icon, label, _, _) = _stages[i];
      children.add(
        _FlowCard(
          icon: icon,
          label: label,
          active: i == _index,
          compact: compact,
          onTap: () => _jump(i),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// One stage of the flow as a fixed-size, tappable card: an icon over a label.
/// All cards share one size so the row reads as a set of equal steps ([compact]
/// shrinks them for mobile). The active card renders in the primary colour
/// (heavier stroke); the rest are muted.
class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = active ? t.colorScheme.primary : t.colorScheme.secondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: SizedBox(
        width: compact ? 64 : 100,
        height: compact ? 64 : 100,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Material Symbols is a variable font: `weight` sets stroke
            // thickness (100–700; lower = finer). The active card thickens to
            // reinforce the highlight; `opticalSize` tunes detail for the size.
            Icon(
              icon,
              size: compact ? 34 : 48,
              weight: active ? 400 : 200,
              opticalSize: 48,
              color: color,
            ),
            SizedBox(height: compact ? AppTokens.space3xs : AppTokens.spaceXs),
            Text(
              label,
              style: (compact ? t.textTheme.bodySmall : t.textTheme.bodyMedium)
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowArrow extends StatelessWidget {
  const _FlowArrow({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? AppTokens.space3xs : AppTokens.spaceXs,
    ),
    child: Icon(
      Icons.arrow_forward,
      size: AppTokens.iconSm,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
