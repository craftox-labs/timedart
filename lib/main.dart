import 'package:flutter/material.dart';
import 'package:time_tracker/theme.dart';
import 'package:time_tracker/screens/time.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Time Tracker',
      theme: buildAppTheme(Brightness.dark),
      home: const TimeScreen(title: 'Time Tracker'),
    );
  }
}
