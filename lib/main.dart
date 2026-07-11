import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/constants/theme.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/onboarding/onboarding_gate.dart';
import 'package:timedart/data/database.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Full-screen (immersive) on mobile — hides the status + navigation bars;
  // swipe from an edge to reveal them temporarily. No-op on desktop/web.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  final db = AppDatabase();
  runApp(MyApp(db: db));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.db});
  final AppDatabase db;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        final scale = width < AppTokens.breakpointMd
            ? 0.85
            : 1.0; // mobile shrink
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: child!,
        );
      },
      title: 'timedart',
      theme: buildAppTheme(Brightness.dark),
      home: RootGate(db: db),
    );
  }
}
