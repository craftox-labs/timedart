import 'package:flutter/material.dart';

class TimerControls extends StatelessWidget {
  final bool running;
  final bool hasSession;
  final int counter;
  final VoidCallback onPrimary; // start / pause / resume
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: onPrimary,
          icon: Icon(running ? Icons.pause : Icons.play_arrow),
          label: Text(running ? 'Pause' : (counter > 0 ? 'Resume' : 'Start')),
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
        OutlinedButton.icon(
          onPressed: onFinish,
          icon: const Icon(Icons.stop),
          label: const Text('Finish'),
          style: OutlinedButton.styleFrom(
            fixedSize: const Size(140, 40),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(0), // inner edge — near-square
                right: Radius.circular(8), // outer edge — rounded
              ),
            ),
          ),
        ),
      ],
    );
  }
}
