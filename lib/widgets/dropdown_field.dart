import 'package:flutter/material.dart';
import 'package:time_tracker/constants/tokens.dart';

/// The chevron for every form select in the app. `DropdownButtonFormField`
/// paints its icon flush against the field's trailing edge regardless of the
/// decoration's contentPadding, so we inset it here — the gap matches an
/// input's left text padding (spaceSm) so selects read the same as text fields.
/// Use as `DropdownButtonFormField(icon: kDropdownChevron, ...)`.
const Widget kDropdownChevron = Padding(
  padding: EdgeInsets.only(right: AppTokens.spaceSm),
  child: Icon(Icons.arrow_drop_down),
);
