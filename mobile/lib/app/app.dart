import 'package:flutter/material.dart';
import 'package:online_prorab/app/theme.dart';
import 'package:online_prorab/features/dashboard/dashboard_screen.dart';

class OnlineProrabApp extends StatelessWidget {
  const OnlineProrabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Online Prorab',
      theme: AppTheme