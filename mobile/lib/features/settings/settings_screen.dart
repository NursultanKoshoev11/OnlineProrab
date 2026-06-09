import 'package:flutter/material.dart';
import 'package:online_prorab/core/config/app_config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: TextStyle(fontSize: 24)),
            SizedBox(height: 12),
            Text('App: ' + AppConfig.appName),
            Text('Mode: ' + AppConfig.buildMode),
          ],
        ),
      ),
    );
  }
}
