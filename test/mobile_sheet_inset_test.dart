import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/widgets/panel.dart';
import 'package:timedart/widgets/sheet_grab_handle.dart';

// Regression guard for the narrow (phone) layout slide-up sheet in AdaptiveShell
// (lib/features/shell/adaptive_shell.dart, the Scaffold returned around line 903;
// the sheet subtree ~1052-1122).
//
// BUG: with Android edge-to-edge + a translucent system nav bar, the CLOSED
// sheet's PanelSearchField leaked into the bottom system inset band. The sheet
// is hidden only by SlideTransition's paint-time translation (Offset(0,1)),
// which does NOT register as layout overflow, so the enclosing Stack pushed no
// clip and the translated-away sheet painted below the body — through the
// bottomNavigationBar's transparent SafeArea inset padding.
//
// FIX: the sheet's outer Positioned.fill is wrapped in a ClipRect, confining the
// paint-time translation to the body bounds. This test reproduces the exact
// sheet subtree (pumping the full shell is non-deterministic — it leaves a
// pending timer from the timer controller / update check) and asserts the
// closed search field's *visible* rect (layout rect clipped by ancestor
// ClipRects) never reaches the inset band.

const double _inset = 48; // simulated Android system nav inset (viewPadding.bottom)
const Size _phone = Size(400, 800); // narrow: width < AppTokens.breakpointMd (760)

final _searchKey = GlobalKey();

// Mirror of AdaptiveShell's narrow Scaffold: appBar + bottomNavigationBar
// (SafeArea top:false, so it insets off the system nav) + a body Stack whose
// third child is the slide-up sheet. [clip] toggles the applied ClipRect so the
// pre-fix (leaking) geometry can be asserted too.
Widget _shellSlice({required bool clip}) {
  final ctrl = AnimationController(
    vsync: const TestVSync(),
    duration: const Duration(milliseconds: 250),
  );
  ctrl.value = 0; // CLOSED: SlideTransition offset == Offset(0, 1)
  final offset = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(ctrl);

  Widget maybeClip(Widget child) => clip ? ClipRect(child: child) : child;

  return Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SafeArea(
            bottom: false,
            child: Container(height: 36, color: scheme.surfaceContainerHighest),
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: AppTokens.strokeThin, color: AppTokens.colorBorder),
            SafeArea(
              top: false,
              child: Material(
                color: scheme.surface,
                child: const SizedBox(height: 64),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: scheme.surface)),
            // The slide-up sheet.
            Positioned.fill(
              child: maybeClip(
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: LayoutBuilder(
                    builder: (context, bodyC) {
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: IgnorePointer(
                          ignoring: true, // closed
                          child: SlideTransition(
                            position: offset,
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
                                child: SafeArea(
                                  top: false,
                                  child: Column(
                                    children: [
                                      const SheetGrabHandle(),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            PanelSearchField(
                                              key: _searchKey,
                                              controller: TextEditingController(),
                                              focusNode: FocusNode(),
                                              onChanged: (_) {},
                                              onEscape: () {},
                                            ),
                                            const Expanded(child: SizedBox()),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
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

Rect _globalRect(RenderBox rb) =>
    MatrixUtils.transformRect(rb.getTransformTo(null), Offset.zero & rb.size);

// The portion of [finder] actually painted on screen: its layout rect clipped by
// every ancestor ClipRect. This is what the SlideTransition-then-ClipRect fix
// governs — getRect() alone reports the (unclipped) layout geometry.
Rect _visibleRect(WidgetTester tester, Finder finder) {
  final leaf = tester.renderObject<RenderBox>(finder);
  var rect = _globalRect(leaf);
  RenderObject? node = leaf.parent;
  while (node != null) {
    if (node is RenderClipRect) {
      rect = rect.intersect(_globalRect(node));
    }
    node = node.parent;
  }
  return rect;
}

Future<void> _pump(WidgetTester tester, {required bool clip}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(bottom: _inset);
  tester.view.viewPadding = const FakeViewPadding(bottom: _inset);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: _shellSlice(clip: clip)));
  await tester.pump();
}

void main() {
  const screenH = 800.0;
  const bandTop = screenH - _inset; // [752, 800] — the system nav inset band

  bool inInsetBand(Rect r) => !r.isEmpty && r.bottom > bandTop && r.top < screenH;

  testWidgets(
    'closed narrow sheet: search field stays clear of the bottom system inset',
    (tester) async {
      await _pump(tester, clip: true);
      final visible = _visibleRect(tester, find.byKey(_searchKey));
      expect(
        inInsetBand(visible),
        isFalse,
        reason: 'closed PanelSearchField must not paint into the [$bandTop, '
            '$screenH] system-nav inset band; visible rect was $visible',
      );
    },
  );

  // Locks in the mechanism: without the ClipRect the closed sheet leaks — this
  // is the exact failure the fix removed.
  testWidgets(
    'pre-fix control: without the ClipRect the closed sheet leaks into the inset',
    (tester) async {
      await _pump(tester, clip: false);
      final visible = _visibleRect(tester, find.byKey(_searchKey));
      expect(inInsetBand(visible), isTrue);
    },
  );
}
