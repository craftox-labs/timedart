import 'package:flutter/material.dart';
import 'package:timedart/constants/tokens.dart';

/// The drag affordance at the top of a bottom sheet — a short rounded bar,
/// centred with standard vertical padding. Shared so every sheet (colour
/// picker, entity editors, the list-panel slide-up) shows the identical handle
/// rather than each hand-rolling its own.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: SizedBox(
        width: 36,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTokens.colorBorder,
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
    ),
  );
}
