import 'package:flutter/material.dart';
import 'package:timedart/widgets/unscaled.dart';

class TimerControls extends StatelessWidget {
  final bool running;
  final bool hasSession;
  final int counter;
  final VoidCallback? onPrimary; // start / pause / resume — null disables it
  final VoidCallback? onFinish; // nullable → disables the button when null

  const TimerControls({
    super.key,
    required this.running,
    required this.hasSession,
    required this.counter,
    required this.onPrimary,
    this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    // The disabled FilledButton container colour (M3): matches the "inactive
    // Start" fill so the Finish outline reads as the same neutral.
    final inactiveFill = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.12);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Unscaled(
          child: Tooltip(
            message: 'Space',
            child: FilledButton.icon(
              onPressed: onPrimary,
              icon: Icon(running ? Icons.pause : Icons.play_arrow),
              label: Text(
                running ? 'Pause' : (counter > 0 ? 'Resume' : 'Start'),
              ),
              style: FilledButton.styleFrom(
                fixedSize: const Size(140, 40),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(8), // outer edge — rounded
                    right: Radius.circular(0), // inner edge — near-square
                  ),
                ),
              ),
            ),
          ),
        ),
        Unscaled(
          child: Tooltip(
            message: 'f',
            child: OutlinedButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.stop),
              label: const Text('Finish'),
              style: OutlinedButton.styleFrom(
                fixedSize: const Size(140, 40),
                side: BorderSide(color: inactiveFill),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(0), // inner edge — near-square
                    right: Radius.circular(8), // outer edge — rounded
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
