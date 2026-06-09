import 'package:flutter/material.dart';
import 'package:onlineprorab/app/theme.dart';
import 'package:onlineprorab/features/dashboard/dashboard_screen.dart';

class OnlineProrabApp extends StatelessWidget {
  const OnlineProrabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Online Prorab',
      theme: AppTheme.light(),
      home: const DashboardScreen(),
    );
  }
}
