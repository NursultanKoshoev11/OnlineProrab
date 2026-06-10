import 'package:flutter/material.dart';

class OnlineProrabApp extends StatelessWidget {
  const OnlineProrabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Online Prorab',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Online Prorab')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Construction control from your phone',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('Track projects, expenses, receipts, daily reports, photos and tasks.'),
            const SizedBox(height: 24),
            const TextField(
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Phone number',
                hintText: '+996...',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProjectsScreen()),
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProjectCard(
            title: 'Demo house project',
            subtitle: 'Expenses, reports and files',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProjectDashboardScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('Project'),
      ),
    );
  }
}

class ProjectDashboardScreen extends StatelessWidget {
  const ProjectDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Project dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SummaryCard(title: 'Total spent', value: '0 KGS'),
          const SizedBox(height: 12),
          const SummaryCard(title: 'Daily reports', value: '0'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            ),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Add expense'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddDailyReportScreen()),
            ),
            icon: const Icon(Icons.assignment),
            label: const Text('Add daily report'),
          ),
        ],
      ),
    );
  }
}

class AddExpenseScreen extends StatelessWidget {
  const AddExpenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DataFormScreen(
      title: 'Add expense',
      fields: ['Title', 'Amount', 'Category', 'Vendor'],
      submitText: 'Save expense',
    );
  }
}

class AddDailyReportScreen extends StatelessWidget {
  const AddDailyReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DataFormScreen(
      title: 'Add daily report',
      fields: ['Summary', 'Workers count', 'Issues'],
      submitText: 'Save report',
    );
  }
}

class DataFormScreen extends StatelessWidget {
  const DataFormScreen({
    required this.title,
    required this.fields,
    required this.submitText,
    super.key,
  });

  final String title;
  final List<String> fields;
  final String submitText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final field in fields) ...[
            TextField(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: field,
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(submitText),
          ),
        ],
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({required this.title, required this.value, super.key});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}
