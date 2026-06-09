import 'package:flutter/material.dart';

class ObjectsScreen extends StatelessWidget {
  const ObjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Objects')),
      body: const Center(child: Text('Objects will load from API')),
    );
  }
}
