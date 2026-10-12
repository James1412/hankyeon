import 'package:flutter/material.dart';

import 'screens/process_practice_screen.dart';

void main() {
  runApp(const HankyeonApp());
}

class HankyeonApp extends StatelessWidget {
  const HankyeonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ProcessPracticeScreen(),
    );
  }
}
