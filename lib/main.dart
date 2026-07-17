import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/constants/theme.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/onboarding/onboarding_gate.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/legacy_db_migration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge on mobile — content draws behind the status + navigation
  // bars, but they stay visible (the standard most apps follow). No-op on
  // desktop/web.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // Rename any pre-1.0 `time_tracker.sqlite` to `timedart.sqlite` before the
  // database opens (no-op on web / fresh installs). Keeps existing users' data.
  await migrateLegacyDatabaseFile();
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
            ? 0.9
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
