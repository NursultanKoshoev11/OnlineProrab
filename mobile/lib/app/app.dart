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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phoneController = TextEditingController(text: '+996');
  final codeController = TextEditingController();
  bool codeRequested = false;

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

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
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Phone number',
                hintText: '+996...',
              ),
            ),
            const SizedBox(height: 12),
            if (codeRequested) ...[
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'SMS code',
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: () {
                if (!codeRequested) {
                  setState(() => codeRequested = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code requested. Connect API client for real SMS.')),
                  );
                  return;
                }
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ProjectsScreen()),
                );
              },
              child: Text(codeRequested ? 'Verify and continue' : 'Request code'),
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
            subtitle: 'Expenses, reports, tasks and files',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProjectDashboardScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => const Padding(
            padding: EdgeInsets.all(16),
            child: DataFormContent(
              fields: ['Project name', 'Address'],
              submitText: 'Create project',
            ),
          ),
        ),
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
          const SizedBox(height: 12),
          const SummaryCard(title: 'Open tasks', value: '0'),
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
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddTaskScreen()),
            ),
            icon: const Icon(Icons.task_alt),
            label: const Text('Add task'),
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

class AddTaskScreen extends StatelessWidget {
  const AddTaskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DataFormScreen(
      title: 'Add task',
      fields: ['Title', 'Description', 'Due date'],
      submitText: 'Save task',
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DataFormContent(fields: fields, submitText: submitText),
      ),
    );
  }
}

class DataFormContent extends StatelessWidget {
  const DataFormContent({required this.fields, required this.submitText, super.key});

  final List<String> fields;
  final String submitText;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
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
