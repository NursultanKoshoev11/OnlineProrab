import 'package:flutter/material.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';

class BackendProjectDashboardScreen extends StatefulWidget {
  const BackendProjectDashboardScreen({
    required this.project,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    super.key,
  });

  final RemoteProject project;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;

  @override
  State<BackendProjectDashboardScreen> createState() => _BackendProjectDashboardScreenState();
}

class _BackendProjectDashboardScreenState extends State<BackendProjectDashboardScreen> {
  late Future<ProjectDashboardData> dashboardFuture;

  @override
  void initState() {
    super.initState();
    dashboardFuture = _load();
  }

  Future<ProjectDashboardData> _load() async {
    final expenses = await widget.costItemRepository.list(widget.project.id);
    final reports = await widget.dailyReportRepository.list(widget.project.id);
    final tasks = await widget.taskRepository.list(widget.project.id);
    return ProjectDashboardData(expenses: expenses, reports: reports, tasks: tasks);
  }

  Future<void> _refresh() async {
    setState(() => dashboardFuture = _load());
    await dashboardFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.project.name.isEmpty ? 'Project' : widget.project.name), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
      body: FutureBuilder<ProjectDashboardData>(
        future: dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return BackendDashboardError(message: _friendlyError(snapshot.error), onRetry: _refresh);
          final data = snapshot.data ?? const ProjectDashboardData(expenses: [], reports: [], tasks: []);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.project.address.isEmpty ? 'No address' : widget.project.address, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    DashboardSummaryCard(title: 'Total spent', value: '${data.totalSpent.toStringAsFixed(0)} KGS'),
                    DashboardSummaryCard(title: 'Reports', value: '${data.reports.length}'),
                    DashboardSummaryCard(title: 'Open tasks', value: '${data.openTasksCount}'),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(onPressed: _addExpense, icon: const Icon(Icons.receipt_long), label: const Text('Expense')),
                    FilledButton.icon(onPressed: _addReport, icon: const Icon(Icons.assignment), label: const Text('Report')),
                    FilledButton.icon(onPressed: _addTask, icon: const Icon(Icons.task_alt), label: const Text('Task')),
                  ],
                ),
                const SizedBox(height: 24),
                DashboardSectionHeader(title: 'Expenses', count: data.expenses.length),
                if (data.expenses.isEmpty) const DashboardEmptyLine('No expenses yet') else ...data.expenses.map((item) => BackendExpenseTile(item: item)),
                const SizedBox(height: 20),
                DashboardSectionHeader(title: 'Daily reports', count: data.reports.length),
                if (data.reports.isEmpty) const DashboardEmptyLine('No reports yet') else ...data.reports.map((item) => BackendReportTile(item: item)),
                const SizedBox(height: 20),
                DashboardSectionHeader(title: 'Tasks', count: data.tasks.length),
                if (data.tasks.isEmpty) const DashboardEmptyLine('No tasks yet') else ...data.tasks.map((item) => BackendTaskTile(item: item, onDone: () => _markTaskDone(item))),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addExpense() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BackendExpenseFormScreen(projectId: widget.project.id, repository: widget.costItemRepository),
    ));
    if (saved == true) await _refresh();
  }

  Future<void> _addReport() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BackendReportFormScreen(projectId: widget.project.id, repository: widget.dailyReportRepository),
    ));
    if (saved == true) await _refresh();
  }

  Future<void> _addTask() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BackendTaskFormScreen(projectId: widget.project.id, repository: widget.taskRepository),
    ));
    if (saved == true) await _refresh();
  }

  Future<void> _markTaskDone(RemoteTask task) async {
    try {
      await widget.taskRepository.markDone(task);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      _showMessage(context, _friendlyError(error));
    }
  }
}

class ProjectDashboardData {
  const ProjectDashboardData({required this.expenses, required this.reports, required this.tasks});

  final List<RemoteCostItem> expenses;
  final List<RemoteDailyReport> reports;
  final List<RemoteTask> tasks;

  double get totalSpent => expenses.fold<double>(0, (sum, item) => sum + item.amount);
  int get openTasksCount => tasks.where((item) => item.status != 'done').length;
}

class BackendExpenseFormScreen extends StatefulWidget {
  const BackendExpenseFormScreen({required this.projectId, required this.repository, super.key});

  final String projectId;
  final CostItemRepository repository;

  @override
  State<BackendExpenseFormScreen> createState() => _BackendExpenseFormScreenState();
}

class _BackendExpenseFormScreenState extends State<BackendExpenseFormScreen> {
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  final categoryController = TextEditingController(text: 'materials');
  final vendorController = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    titleController.dispose();
    amountController.dispose();
    categoryController.dispose();
    vendorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: titleController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Amount, KGS')),
          const SizedBox(height: 12),
          TextField(controller: categoryController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Category')),
          const SizedBox(height: 12),
          TextField(controller: vendorController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Vendor')),
          const SizedBox(height: 16),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (error != null) const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : _save, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save expense')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = titleController.text.trim();
    final amount = double.tryParse(amountController.text.trim());
    if (title.isEmpty || amount == null || amount < 0) {
      setState(() => error = 'Enter valid title and amount');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.create(projectId: widget.projectId, title: title, amount: amount, category: categoryController.text.trim(), vendor: vendorController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class BackendReportFormScreen extends StatefulWidget {
  const BackendReportFormScreen({required this.projectId, required this.repository, super.key});

  final String projectId;
  final DailyReportRepository repository;

  @override
  State<BackendReportFormScreen> createState() => _BackendReportFormScreenState();
}

class _BackendReportFormScreenState extends State<BackendReportFormScreen> {
  final summaryController = TextEditingController();
  final workersController = TextEditingController(text: '1');
  final issuesController = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    summaryController.dispose();
    workersController.dispose();
    issuesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: summaryController, minLines: 3, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Work summary')),
          const SizedBox(height: 12),
          TextField(controller: workersController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Workers count')),
          const SizedBox(height: 12),
          TextField(controller: issuesController, minLines: 2, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Issues / delays')),
          const SizedBox(height: 16),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (error != null) const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : _save, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save report')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final summary = summaryController.text.trim();
    final workers = int.tryParse(workersController.text.trim());
    if (summary.isEmpty || workers == null || workers < 0) {
      setState(() => error = 'Enter valid summary and workers count');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.create(projectId: widget.projectId, summary: summary, workersCount: workers, issues: issuesController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class BackendTaskFormScreen extends StatefulWidget {
  const BackendTaskFormScreen({required this.projectId, required this.repository, super.key});

  final String projectId;
  final TaskRepository repository;

  @override
  State<BackendTaskFormScreen> createState() => _BackendTaskFormScreenState();
}

class _BackendTaskFormScreenState extends State<BackendTaskFormScreen> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add task')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: titleController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(controller: descriptionController, minLines: 3, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Description')),
          const SizedBox(height: 16),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (error != null) const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : _save, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save task')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = titleController.text.trim();
    if (title.isEmpty) {
      setState(() => error = 'Task title is required');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.create(projectId: widget.projectId, title: title, description: descriptionController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class BackendExpenseTile extends StatelessWidget {
  const BackendExpenseTile({required this.item, super.key});
  final RemoteCostItem item;

  @override
  Widget build(BuildContext context) {
    final vendor = item.vendor.isEmpty ? '' : ' • ${item.vendor}';
    return Card(child: ListTile(leading: const Icon(Icons.receipt_long), title: Text(item.title), subtitle: Text('${item.category}$vendor'), trailing: Text('${item.amount.toStringAsFixed(0)} ${item.currency}')));
  }
}

class BackendReportTile extends StatelessWidget {
  const BackendReportTile({required this.item, super.key});
  final RemoteDailyReport item;

  @override
  Widget build(BuildContext context) {
    final issues = item.issues.isEmpty ? '' : ' • Issues: ${item.issues}';
    return Card(child: ListTile(leading: const Icon(Icons.assignment), title: Text(item.summary), subtitle: Text('${item.workersCount} workers$issues')));
  }
}

class BackendTaskTile extends StatelessWidget {
  const BackendTaskTile({required this.item, required this.onDone, super.key});
  final RemoteTask item;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Card(child: ListTile(leading: Icon(item.status == 'done' ? Icons.check_circle : Icons.radio_button_unchecked), title: Text(item.title), subtitle: Text(item.description.isEmpty ? item.status : '${item.description} • ${item.status}'), trailing: item.status == 'done' ? null : TextButton(onPressed: onDone, child: const Text('Done'))));
  }
}

class DashboardSummaryCard extends StatelessWidget {
  const DashboardSummaryCard({required this.title, required this.value, super.key});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 160, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 8), Text(value, style: Theme.of(context).textTheme.headlineSmall)]))));
  }
}

class DashboardSectionHeader extends StatelessWidget {
  const DashboardSectionHeader({required this.title, required this.count, super.key});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)), Text('$count total', style: Theme.of(context).textTheme.bodySmall)]);
  }
}

class DashboardEmptyLine extends StatelessWidget {
  const DashboardEmptyLine(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(message, style: Theme.of(context).textTheme.bodyMedium));
  }
}

class BackendDashboardError extends StatelessWidget {
  const BackendDashboardError({required this.message, required this.onRetry, super.key});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 56), const SizedBox(height: 16), Text('Could not load dashboard', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry'))])));
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _friendlyError(Object? error) {
  final text = error.toString();
  if (text.contains('408') || text.contains('timed out')) return 'Server timeout. Check internet or backend status.';
  if (text.contains('401')) return 'Session expired. Please sign in again.';
  if (text.contains('Connection refused') || text.contains('ApiException(0)')) return 'Cannot connect to backend. Check API_BASE_URL and server status.';
  if (text.contains('invalid JSON')) return 'Backend returned an invalid response.';
  return text.replaceFirst('Exception: ', '');
}
