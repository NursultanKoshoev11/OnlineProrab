import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Online Prorab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _MetricCard(title: 'Projects', value: '0'),
          _MetricCard(title: 'Pending costs', value: '0'),
          _MetricCard(title: 'Daily reports', value: '0'),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
