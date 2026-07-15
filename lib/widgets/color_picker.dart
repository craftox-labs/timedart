import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/constants/layout.dart';
import 'package:timedart/constants/tokens.dart';

/// Opens an HSV colour picker and resolves to the chosen opaque ARGB int, or
/// null if dismissed. A saturation/brightness field plus a hue slider give a
/// "pick it off the spectrum" experience for non-technical users, with a hex
/// field for anyone who knows the code they want. Alpha is always forced opaque
/// — template swatches are solid.
///
/// Presentation follows the layout: a bottom sheet on a phone (thumb-reachable
/// from the bottom edge), a centred dialog on desktop.
Future<int?> showColorPicker(
  BuildContext context, {
  required int initial,
  required String label,
}) {
  if (context.isNarrow) {
    // Surface, shape and elevation come from the app's bottomSheetTheme.
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ColorPickerBody(initial: initial, label: label),
    );
  }
  return showDialog<int>(
    context: context,
    builder: (_) => Dialog(
      // Background/shape come from the app's dialogTheme.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: _ColorPickerBody(initial: initial, label: label, sheet: false),
      ),
    ),
  );
}

// The saturation/brightness field's height; width flexes to the sheet.
const double _fieldHeight = 200;
const double _hueHeight = 28;
const double _thumbR = 11;

// Rainbow stops for the hue track (0°…360°, wrapping back to red).
const List<Color> _hueColors = [
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF00FF00),
  Color(0xFF00FFFF),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

class _ColorPickerBody extends StatefulWidget {
  const _ColorPickerBody({
    required this.initial,
    required this.label,
    this.sheet = true,
  });
  final int initial;
  final String label;
  // Bottom-sheet chrome (grab handle + keyboard inset); false in the desktop
  // dialog, which centres and lifts above the keyboard on its own.
  final bool sheet;

  @override
  State<_ColorPickerBody> createState() => _ColorPickerBodyState();
}

class _ColorPickerBodyState extends State<_ColorPickerBody> {
  late HSVColor _hsv;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(Color(widget.initial));
    _hex = TextEditingController(text: _toHex(_color));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  // Always opaque — drop whatever alpha HSV round-tripping produced.
  Color get _color => _hsv.toColor().withAlpha(0xFF);
  int get _argb => _color.toARGB32();

  static String _toHex(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _set(HSVColor next) {
    setState(() {
      _hsv = next;
      final hex = _toHex(_color);
      if (hex != _hex.text.toUpperCase()) _hex.text = hex;
    });
  }

  void _applyHex(String raw) {
    final s = raw.trim().replaceAll('#', '');
    if (s.length != 6) return;
    final v = int.tryParse(s, radix: 16);
    if (v != null) setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | v)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        // Sheet: lift above the keyboard when the hex field is focused. Dialog:
        // it recentres itself, so a plain even inset.
        padding: EdgeInsets.only(
          left: AppTokens.spaceLg,
          right: AppTokens.spaceLg,
          top: widget.sheet ? AppTokens.spaceMd : AppTokens.spaceLg,
          bottom:
              AppTokens.spaceLg +
              (widget.sheet ? MediaQuery.viewInsetsOf(context).bottom : 0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle (sheet only).
            if (widget.sheet)
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: AppTokens.colorBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Row(
              children: [
                Text(widget.label, style: theme.textTheme.titleMedium),
                const Spacer(),
                _swatch(),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMd),
            _satBrightnessField(),
            const SizedBox(height: AppTokens.spaceMd),
            _hueTrack(),
            const SizedBox(height: AppTokens.spaceMd),
            _hexField(),
            const SizedBox(height: AppTokens.spaceLg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _argb),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatch() => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: _color,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      border: Border.all(color: AppTokens.colorBorder),
    ),
  );

  // Saturation left→right, brightness top→bottom, over the current hue.
  Widget _satBrightnessField() {
    final hueColor = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void handle(Offset p) {
          _set(
            _hsv
                .withSaturation((p.dx / w).clamp(0.0, 1.0))
                .withValue(1 - (p.dy / _fieldHeight).clamp(0.0, 1.0)),
          );
        }

        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            child: SizedBox(
              width: w,
              height: _fieldHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Colors.white, hueColor],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _hsv.saturation * w - _thumbR,
                    top: (1 - _hsv.value) * _fieldHeight - _thumbR,
                    child: _thumb(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hueTrack() {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void handle(Offset p) =>
            _set(_hsv.withHue((p.dx / w).clamp(0.0, 1.0) * 360));

        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            child: SizedBox(
              width: w,
              height: _hueHeight,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: _hueColors),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _hsv.hue / 360 * w - _thumbR,
                    top: _hueHeight / 2 - _thumbR,
                    child: _thumb(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _thumb() => Container(
    width: _thumbR * 2,
    height: _thumbR * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: _color,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2)],
    ),
  );

  Widget _hexField() => TextField(
    controller: _hex,
    textCapitalization: TextCapitalization.characters,
    decoration: const InputDecoration(labelText: 'Hex', prefixText: '#'),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
      LengthLimitingTextInputFormatter(6),
    ],
    onChanged: _applyHex,
  );
}
