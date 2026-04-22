import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MotomanFixApp());
}

class MotomanFixApp extends StatelessWidget {
  const MotomanFixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RAM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005691),
          primary: const Color(0xFF005691),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F7FB),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          elevation: 1.5,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
