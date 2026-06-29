import 'package:flutter/material.dart';
import 'package:time_tracker/theme.dart';
import 'package:time_tracker/screens/adaptive_shell.dart';
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
      title: 'Time Tracker',
      theme: buildAppTheme(Brightness.dark),
      home: AdaptiveShell(db: db),
    );
  }
}
