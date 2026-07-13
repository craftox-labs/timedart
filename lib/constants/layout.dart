import 'package:flutter/material.dart';
import 'package:timedart/constants/tokens.dart';

extension LayoutQuery on BuildContext {
  bool get isNarrow => MediaQuery.sizeOf(this).width < AppTokens.breakpointMd;

  /// Width a leading/trailing tap target occupies as a layout column:
  /// a full touch target on narrow, else [wide] (typically the glyph's size).
  double tapColumn(double wide) => isNarrow ? AppTokens.minTouchTarget : wide;
}
