import 'package:flutter/material.dart';
import 'package:time_tracker/constants/theme.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/shell/adaptive_shell.dart';
import 'package:time_tracker/data/database.dart';

void main() {
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
      title: 'Time Tracker',
      theme: buildAppTheme(Brightness.dark),
      home: AdaptiveShell(db: db),
    );
  }
}
