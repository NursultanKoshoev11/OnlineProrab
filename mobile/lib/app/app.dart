import 'package:flutter/material.dart';

class OnlineProrabApp extends StatefulWidget {
  const OnlineProrabApp({super.key});

  @override
  State<OnlineProrabApp> createState() => _OnlineProrabAppState();
}

class _OnlineProrabAppState extends State<OnlineProrabApp> {
  final appState = AppState();

  @override
  void dispose() {
    appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: appState,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Online Prorab',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required AppState state, required super.child, super.key}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in context');
    return scope!.notifier!;
  }
}

class AppState extends ChangeNotifier {
  bool isSignedIn = false;
  String phone = '';
  final List<ProjectItem> projects = [];
  final List<ExpenseItem> expenses = [];
  final List<DailyReportItem> reports = [];
  final List<TaskItem> tasks = [];

  void signIn(String phoneNumber) {
    phone = phoneNumber.trim();
    isSignedIn = true;
    notifyListeners();
  }

  ProjectItem addProject({required String name, required String address}) {
    final item = ProjectItem(
      id: _newId('project'),
      name: name.trim(),
      address: address.trim(),
      status: 'active',
      createdAt: DateTime.now(),
    );
    projects.insert(0, item);
    notifyListeners();
    return item;
  }

  void updateProject(ProjectItem project, {required String name, required String address}) {
    project.name = name.trim();
    project.address = address.trim();
    notifyListeners();
  }

  void deleteProject(String projectId) {
    projects.removeWhere((item) => item.id == projectId);
    expenses.removeWhere((item) => item.projectId == projectId);
    reports.removeWhere((item) => item.projectId == projectId);
    tasks.removeWhere((item) => item.projectId == projectId);
    notifyListeners();
  }

  ExpenseItem addExpense({
    required String projectId,
    required String title,
    required double amount,
    required String category,
    required String vendor,
  }) {
    final item = ExpenseItem(
      id: _newId('expense'),
      projectId: projectId,
      title: title.trim(),
      amount: amount,
      category: category.trim().isEmpty ? 'other' : category.trim(),
      vendor: vendor.trim(),
      spentAt: DateTime.now(),
    );
    expenses.insert(0, item);
    notifyListeners();
    return item;
  }

  DailyReportItem addReport({
    required String projectId,
    required String summary,
    required int workersCount,
    required String issues,
  }) {
    final item = DailyReportItem(
      id: _newId('report'),
      projectId: projectId,
      summary: summary.trim(),
      workersCount: workersCount,
      issues: issues.trim(),
      reportDate: DateTime.now(),
    );
    reports.insert(0, item);
    notifyListeners();
    return item;
  }

  TaskItem addTask({
    required String projectId,
    required String title,
    required String description,
  }) {
    final item = TaskItem(
      id: _newId('task'),
      projectId: projectId,
      title: title.trim(),
      description: description.trim(),
      status: 'open',
      createdAt: DateTime.now(),
    );
    tasks.insert(0, item);
    notifyListeners();
    return item;
  }

  void markTaskDone(String taskId) {
    for (final task in tasks) {
      if (task.id == taskId) {
        task.status = 'done';
        break;
      }
    }
    notifyListeners();
  }

  ProjectItem? projectById(String projectId) {
    for (final project in projects) {
      if (project.id == projectId) {
        return project;
      }
    }
    return null;
  }

  List<ExpenseItem> expensesFor(String projectId) => expenses.where((item) => item.projectId == projectId).toList();
  List<DailyReportItem> reportsFor(String projectId) => reports.where((item) => item.projectId == projectId).toList();
  List<TaskItem> tasksFor(String projectId) => tasks.where((item) => item.projectId == projectId).toList();

  double totalSpent(String projectId) {
    return expensesFor(projectId).fold<double>(0, (sum, item) => sum + item.amount);
  }

  int openTasksCount(String projectId) {
    return tasksFor(projectId).where((item) => item.status != 'done').length;
  }

  String _newId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

class ProjectItem {
  ProjectItem({required this.id, required this.name, required this.address, required this.status, required this.createdAt});

  final String id;
  String name;
  String address;
  String status;
  final DateTime createdAt;
}

class ExpenseItem {
  ExpenseItem({required this.id, required this.projectId, required this.title, required this.amount, required this.category, required this.vendor, required this.spentAt});

  final String id;
  final String projectId;
  final String title;
  final double amount;
  final String category;
  final String vendor;
  final DateTime spentAt;
}

class DailyReportItem {
  DailyReportItem({required this.id, required this.projectId, required this.summary, required this.workersCount, required this.issues, required this.reportDate});

  final String id;
  final String projectId;
  final String summary;
  final int workersCount;
  final String issues;
  final DateTime reportDate;
}

class TaskItem {
  TaskItem({required this.id, required this.projectId, required this.title, required this.description, required this.status, required this.createdAt});

  final String id;
  final String projectId;
  final String title;
  final String description;
  String status;
  final DateTime createdAt;
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
      body: SafeArea(
        child: Padding(
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
                    helperText: 'MVP mode: enter any 6 digits',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: () => _submit(context),
                child: Text(codeRequested ? 'Verify and continue' : 'Request code'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit(BuildContext context) {
    final phone = phoneController.text.trim();
    if (phone.length < 9) {
      _showMessage(context, 'Enter a valid phone number');
      return;
    }
    if (!codeRequested) {
      setState(() => codeRequested = true);
      _showMessage(context, 'Code requested. API connection will replace MVP verification.');
      return;
    }
    if (codeController.text.trim().length != 6) {
      _showMessage(context, 'Enter 6-digit code');
      return;
    }
    AppScope.of(context).signIn(phone);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ProjectsScreen()));
  }
}

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final projects = state.projects;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            tooltip: 'Signed in phone',
            onPressed: () => _showMessage(context, 'Signed in as ${state.phone}'),
            icon: const Icon(Icons.account_circle),
          ),
        ],
      ),
      body: projects.isEmpty
          ? const EmptyState(
              icon: Icons.home_work_outlined,
              title: 'No projects yet',
              message: 'Create your first house project to start tracking expenses, reports and tasks.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final project = projects[index];
                return ProjectCard(
                  project: project,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ProjectDashboardScreen(projectId: project.id)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProjectFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Project'),
      ),
    );
  }
}

class ProjectFormScreen extends StatefulWidget {
  const ProjectFormScreen({this.project, super.key});

  final ProjectItem? project;

  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  late final TextEditingController nameController;
  late final TextEditingController addressController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.project?.name ?? '');
    addressController = TextEditingController(text: widget.project?.address ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.project != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit project' : 'Create project')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Project name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: addressController,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Address'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                _showMessage(context, 'Project name is required');
                return;
              }
              final state = AppScope.of(context);
              if (widget.project == null) {
                state.addProject(name: name, address: addressController.text);
              } else {
                state.updateProject(widget.project!, name: name, address: addressController.text);
              }
              Navigator.of(context).pop();
            },
            child: Text(isEdit ? 'Save project' : 'Create project'),
          ),
        ],
      ),
    );
  }
}

class ProjectDashboardScreen extends StatelessWidget {
  const ProjectDashboardScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final project = state.projectById(projectId);
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Project not found')),
        body: const EmptyState(icon: Icons.error_outline, title: 'Project not found', message: 'This project was deleted or is unavailable.'),
      );
    }

    final expenses = state.expensesFor(projectId);
    final reports = state.reportsFor(projectId);
    final tasks = state.tasksFor(projectId);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            tooltip: 'Edit project',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectFormScreen(project: project))),
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(project.address.isEmpty ? 'No address' : project.address, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SummaryCard(title: 'Total spent', value: '${state.totalSpent(projectId).toStringAsFixed(0)} KGS'),
              SummaryCard(title: 'Reports', value: '${reports.length}'),
              SummaryCard(title: 'Open tasks', value: '${state.openTasksCount(projectId)}'),
            ],
          ),
          const SizedBox(height: 20),
          ActionGrid(projectId: projectId),
          const SizedBox(height: 24),
          SectionHeader(title: 'Recent expenses', actionText: expenses.isEmpty ? null : '${expenses.length} total'),
          if (expenses.isEmpty)
            const SmallEmptyState(message: 'No expenses yet')
          else
            ...expenses.take(5).map((item) => ExpenseTile(item: item)),
          const SizedBox(height: 20),
          SectionHeader(title: 'Daily reports', actionText: reports.isEmpty ? null : '${reports.length} total'),
          if (reports.isEmpty)
            const SmallEmptyState(message: 'No daily reports yet')
          else
            ...reports.take(5).map((item) => ReportTile(item: item)),
          const SizedBox(height: 20),
          SectionHeader(title: 'Tasks', actionText: tasks.isEmpty ? null : '${tasks.length} total'),
          if (tasks.isEmpty)
            const SmallEmptyState(message: 'No tasks yet')
          else
            ...tasks.map((item) => TaskTile(item: item)),
        ],
      ),
    );
  }
}

class ActionGrid extends StatelessWidget {
  const ActionGrid({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExpenseFormScreen(projectId: projectId))),
          icon: const Icon(Icons.receipt_long),
          label: const Text('Expense'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DailyReportFormScreen(projectId: projectId))),
          icon: const Icon(Icons.assignment),
          label: const Text('Report'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskFormScreen(projectId: projectId))),
          icon: const Icon(Icons.task_alt),
          label: const Text('Task'),
        ),
      ],
    );
  }
}

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({required this.projectId, super.key});

  final String projectId;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  final categoryController = TextEditingController(text: 'materials');
  final vendorController = TextEditingController();

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
          FilledButton(onPressed: _save, child: const Text('Save expense')),
        ],
      ),
    );
  }

  void _save() {
    final title = titleController.text.trim();
    final amount = double.tryParse(amountController.text.trim());
    if (title.isEmpty || amount == null || amount < 0) {
      _showMessage(context, 'Enter valid title and amount');
      return;
    }
    AppScope.of(context).addExpense(
      projectId: widget.projectId,
      title: title,
      amount: amount,
      category: categoryController.text,
      vendor: vendorController.text,
    );
    Navigator.of(context).pop();
  }
}

class DailyReportFormScreen extends StatefulWidget {
  const DailyReportFormScreen({required this.projectId, super.key});

  final String projectId;

  @override
  State<DailyReportFormScreen> createState() => _DailyReportFormScreenState();
}

class _DailyReportFormScreenState extends State<DailyReportFormScreen> {
  final summaryController = TextEditingController();
  final workersController = TextEditingController(text: '1');
  final issuesController = TextEditingController();

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
      appBar: AppBar(title: const Text('Add daily report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: summaryController, minLines: 3, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Work summary')),
          const SizedBox(height: 12),
          TextField(controller: workersController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Workers count')),
          const SizedBox(height: 12),
          TextField(controller: issuesController, minLines: 2, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Issues / delays')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save report')),
        ],
      ),
    );
  }

  void _save() {
    final summary = summaryController.text.trim();
    final workers = int.tryParse(workersController.text.trim());
    if (summary.isEmpty || workers == null || workers < 0) {
      _showMessage(context, 'Enter valid summary and workers count');
      return;
    }
    AppScope.of(context).addReport(projectId: widget.projectId, summary: summary, workersCount: workers, issues: issuesController.text);
    Navigator.of(context).pop();
  }
}

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({required this.projectId, super.key});

  final String projectId;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();

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
          FilledButton(onPressed: _save, child: const Text('Save task')),
        ],
      ),
    );
  }

  void _save() {
    final title = titleController.text.trim();
    if (title.isEmpty) {
      _showMessage(context, 'Task title is required');
      return;
    }
    AppScope.of(context).addTask(projectId: widget.projectId, title: title, description: descriptionController.text);
    Navigator.of(context).pop();
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({required this.project, required this.onTap, super.key});

  final ProjectItem project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Card(
      child: ListTile(
        title: Text(project.name),
        subtitle: Text('${project.address.isEmpty ? 'No address' : project.address} • ${state.expensesFor(project.id).length} expenses'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({required this.item, super.key});

  final ExpenseItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long),
        title: Text(item.title),
        subtitle: Text('${item.category}${item.vendor.isEmpty ? '' : ' • ${item.vendor}'}'),
        trailing: Text('${item.amount.toStringAsFixed(0)} KGS'),
      ),
    );
  }
}

class ReportTile extends StatelessWidget {
  const ReportTile({required this.item, super.key});

  final DailyReportItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.assignment),
        title: Text(item.summary),
        subtitle: Text('${_formatDate(item.reportDate)} • ${item.workersCount} workers${item.issues.isEmpty ? '' : ' • Issues: ${item.issues}'}'),
      ),
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({required this.item, super.key});

  final TaskItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(item.status == 'done' ? Icons.check_circle : Icons.radio_button_unchecked),
        title: Text(item.title),
        subtitle: Text(item.description.isEmpty ? item.status : '${item.description} • ${item.status}'),
        trailing: item.status == 'done'
            ? null
            : TextButton(
                onPressed: () => AppScope.of(context).markTaskDone(item.id),
                child: const Text('Done'),
              ),
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
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.actionText, super.key});

  final String title;
  final String? actionText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (actionText != null) Text(actionText!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, required this.message, super.key});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class SmallEmptyState extends StatelessWidget {
  const SmallEmptyState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
