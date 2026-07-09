import 'dart:typed_data';

import 'package:animations/animations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/invoices/editor_common.dart';
import 'package:time_tracker/features/invoices/invoice_region.dart';
import 'package:time_tracker/features/onboarding/onboarding_controller.dart';
import 'package:time_tracker/features/onboarding/onboarding_machine.dart';

// The first-run onboarding wizard (PRD #133, phase d). A full-screen stepped
// flow driven by [OnboardingMachine]: Welcome → How it works → Your business →
// Your region → Done. Orientation precedes any input; every input step is
// skippable (leave the fields blank and continue, or "Skip setup" entirely) and
// whatever is captured is applied to the seeded default profile by the root
// gate via [applyOnboarding].
//
// The "How it works" diagram is a static placeholder here — phase (f) animates
// the Client → Project → Task → Timer → Invoice sequence. The startup intro
// animation is phase (e), ahead of the gate.
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
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceXl,
                    vertical: AppTokens.spaceLg,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageTransitionSwitcher(
                          transitionBuilder: (child, primary, secondary) =>
                              FadeThroughTransition(
                                animation: primary,
                                secondaryAnimation: secondary,
                                fillColor: Colors.transparent,
                                child: child,
                              ),
                          child: KeyedSubtree(
                            key: ValueKey(_machine.current),
                            child: _stepBody(_machine.current, narrow),
                          ),
                        ),
                        // Welcome's primary sits right below its byline; every
                        // other step uses the fixed bottom nav so its buttons
                        // land at a consistent height across screens.
                        if (_machine.isFirst) ...[
                          const SizedBox(height: AppTokens.space2xl),
                          _entranceSlide(
                            Center(child: _primaryButton()),
                            const Offset(0, 1),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!_machine.isFirst) _bottomNav(),
          ],
        ),
      ),
    );
  }

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
              style: TextButton.styleFrom(shape: _buttonShape),
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
      child: Text(label),
    );
  }

  static final _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
  );

  // ── Step bodies ─────────────────────────────────────────────────────────

  Widget _stepBody(OnboardingStep step, bool narrow) => switch (step) {
    OnboardingStep.welcome => _welcome(narrow),
    OnboardingStep.howItWorks => _howItWorks(narrow),
    OnboardingStep.business => _business(),
    OnboardingStep.region => _region_(),
    OnboardingStep.done => _done(),
  };

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

  // FIXME(#137): the how-it-works diagram is a placeholder — needs design work
  // (bespoke illustrations, animated reveal, tidier mobile layout). Phase (f).
  static const _flowCards = [
    _FlowCard(Symbols.person, 'Client'),
    _FlowArrow(),
    _FlowCard(Symbols.folder, 'Project'),
    _FlowArrow(),
    _FlowCard(Symbols.check_circle, 'Task'),
    _FlowArrow(),
    _FlowCard(Symbols.timer, 'Timer'),
    _FlowArrow(),
    _FlowCard(Symbols.receipt_long, 'Invoice'),
  ];

  Widget _howItWorks(bool narrow) => _CenteredStep(
    children: [
      _title('How timedart works'),
      const SizedBox(height: AppTokens.spaceLg),
      // Wide: one row, scaling down if tight. Narrow (mobile): keep the cards
      // full size and wrap onto multiple rows instead of shrinking.
      if (narrow)
        const Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppTokens.spaceXs,
          runSpacing: AppTokens.spaceSm,
          children: _flowCards,
        )
      else
        const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: _flowCards),
        ),
      const SizedBox(height: AppTokens.spaceLg),
      _body(
        'Log time under a client\'s project and its tasks, then turn those '
        'hours into an invoice.',
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
      Icon(
        Icons.check_circle_outline,
        size: 120,
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
        Text(title, style: t.textTheme.headlineSmall),
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

/// One stage of the flow as a fixed-size card: an icon over a label. All cards
/// share [_size] so the row reads as a set of equal steps.
class _FlowCard extends StatelessWidget {
  const _FlowCard(this.icon, this.label);
  final IconData icon;
  final String label;

  static const double _size = 120;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: _size,
      height: _size,
      padding: const EdgeInsets.all(AppTokens.spaceXs),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: AppTokens.colorBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Material Symbols is a variable font: `weight` sets stroke thickness
          // (100–700; lower = finer) and `opticalSize` tunes detail for the
          // rendered size. Dial these to taste.
          Icon(
            icon,
            size: 64,
            weight: 200,
            opticalSize: 48,
            color: t.colorScheme.primary,
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(label, style: t.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _FlowArrow extends StatelessWidget {
  const _FlowArrow();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceXs),
    child: Icon(
      Icons.arrow_forward,
      size: AppTokens.iconSm,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
