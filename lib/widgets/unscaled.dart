import 'package:flutter/material.dart';

/// Opts its child out of the app-wide text downscale — used on button labels
/// so they keep full size for tap/readability on small screens.
class Unscaled extends StatelessWidget {
  const Unscaled({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      MediaQuery.withNoTextScaling(child: child);
}
