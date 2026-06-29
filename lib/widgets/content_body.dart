import 'package:flutter/material.dart';
import 'package:time_tracker/tokens.dart';

class ContentBody extends StatelessWidget {
  final Widget child;
  const ContentBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppTokens.maxContentWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
        child: child,
      ),
    ),
  );
}
