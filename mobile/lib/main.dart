import 'package:flutter/material.dart';

void main() {
  runApp(const OnlineProrabApp());
}

class OnlineProrabApp extends StatelessWidget {
  const OnlineProrabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(child: Text('Online Prorab MVP')),
      ),
    );
  }
}
