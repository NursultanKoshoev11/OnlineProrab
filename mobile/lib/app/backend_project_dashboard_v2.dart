import 'package:flutter/material.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';

class BackendProjectDashboardScreenV2 extends StatefulWidget {
  const BackendProjectDashboardScreenV2({
    required this.project,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    required this.fileRepository,
    super.key,
  });

  final RemoteProject project;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;

  @override
  State<BackendProjectDashboardScreenV2> createState() => _BackendProjectDashboardScreenV2State();
}

class _BackendProjectDashboardScreenV2State extends State<BackendProjectDashboardScreenV2> {
  late Future<ProjectDashboardDataV2> dashboardFuture;

  @override
  void initState() {
    super.initState();
    dashboardFuture = _load();
  }

  Future<ProjectDashboardDataV2> _load() async {
    final expenses = await widget.costItemRepository.list(widget.project.id);
    final reports = await widget.dailyReportRepository.list(widget.project.id);
    final tasks = await widget.taskRepository.list(widget.project.id);
    final files = await widget.fileRepository.list(widget.project.id);
    return ProjectDashboardDataV2(expenses: expenses, reports: reports, tasks: tasks, files: files);
  }

  Future<void> _refresh() async {
    setState(() => dashboardFuture = _load());
    await dashboardFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.project.name.isEmpty ? 'Project' : widget.project.name), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))]),
      body: FutureBuilder<ProjectDashboardDataV2>(
        future: dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return BackendDashboardErrorV2(message: _friendlyError(snapshot.error), onRetry: _refresh);
          final data = snapshot.data ?? const ProjectDashboardDataV2(expenses: [], reports: [], tasks: [], files: []);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.project.address.isEmpty ? 'No address' : widget.project.address, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  DashboardSummaryCardV2(title: 'Total spent', value: '${data.totalSpent.toStringAsFixed(0)} KGS'),
                  DashboardSummaryCardV2(title: 'Reports', value: '${data.reports.length}'),
                  DashboardSummaryCardV2(title: 'Open tasks', value: '${data.openTasksCount}'),
                  DashboardSummaryCardV2(title: 'Files', value: '${data.files.length}'),
                ]),
                const SizedBox(height: 20),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(onPressed: _addExpense, icon: const Icon(Icons.receipt_long), label: const Text('Expense')),
                  FilledButton.icon(onPressed: _addReport, icon: const Icon(Icons.assignment), label: const Text('Report')),
                  FilledButton.icon(onPressed: _addTask, icon: const Icon(Icons.task_alt), label: const Text('Task')),
                  FilledButton.icon(onPressed: _addFile, icon: const Icon(Icons.attach_file), label: const Text('File record')),
                ]),
                const SizedBox(height: 24),
                DashboardSectionHeaderV2(title: 'Expenses', count: data.expenses.length),
                if (data.expenses.isEmpty) const DashboardEmptyLineV2('No expenses yet') else ...data.expenses.map((item) => BackendExpenseTileV2(item: item)),
                const SizedBox(height: 20),
                DashboardSectionHeaderV2(title: 'Daily reports', count: data.reports.length),
                if (data.reports.isEmpty) const DashboardEmptyLineV2('No reports yet') else ...data.reports.map((item) => BackendReportTileV2(item: item)),
                const SizedBox(height: 20),
                DashboardSectionHeaderV2(title: 'Tasks', count: data.tasks.length),
                if (data.tasks.isEmpty) const DashboardEmptyLineV2('No tasks yet') else ...data.tasks.map((item) => BackendTaskTileV2(item: item, onDone: () => _markTaskDone(item))),
                const SizedBox(height: 20),
                DashboardSectionHeaderV2(title: 'Files', count: data.files.length),
                if (data.files.isEmpty) const DashboardEmptyLineV2('No files yet') else ...data.files.map((item) => BackendFileTileV2(item: item)),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addExpense() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BackendExpenseFormScreenV2(projectId: widget.project.id, repository: widget.costItemRepository)));
    if (saved == true) await _refresh();
  }

  Future<void> _addReport() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BackendReportFormScreenV2(projectId: widget.project.id, repository: widget.dailyReportRepository)));
    if (saved == true) await _refresh();
  }

  Future<void> _addTask() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BackendTaskFormScreenV2(projectId: widget.project.id, repository: widget.taskRepository)));
    if (saved == true) await _refresh();
  }

  Future<void> _addFile() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BackendFileFormScreenV2(projectId: widget.project.id, repository: widget.fileRepository)));
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

class ProjectDashboardDataV2 {
  const ProjectDashboardDataV2({required this.expenses, required this.reports, required this.tasks, required this.files});
  final List<RemoteCostItem> expenses;
  final List<RemoteDailyReport> reports;
  final List<RemoteTask> tasks;
  final List<RemoteProjectFile> files;
  double get totalSpent => expenses.fold<double>(0, (sum, item) => sum + item.amount);
  int get openTasksCount => tasks.where((item) => item.status != 'done').length;
}

class BackendFileFormScreenV2 extends StatefulWidget {
  const BackendFileFormScreenV2({required this.projectId, required this.repository, super.key});
  final String projectId;
  final ProjectFileRepository repository;
  @override
  State<BackendFileFormScreenV2> createState() => _BackendFileFormScreenV2State();
}

class _BackendFileFormScreenV2State extends State<BackendFileFormScreenV2> {
  final originalNameController = TextEditingController();
  final storagePathController = TextEditingController();
  final sizeController = TextEditingController(text: '0');
  String kind = 'receipt';
  String contentType = 'image/jpeg';
  bool busy = false;
  String? error;

  @override
  void dispose() {
    originalNameController.dispose();
    storagePathController.dispose();
    sizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add file record')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('This saves file metadata to backend. Binary upload can be added after storage is configured.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: kind, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Kind'), items: const [DropdownMenuItem(value: 'receipt', child: Text('Receipt')), DropdownMenuItem(value: 'photo', child: Text('Photo')), DropdownMenuItem(value: 'document', child: Text('Document'))], onChanged: (value) => setState(() => kind = value ?? 'document')),
        const SizedBox(height: 12),
        TextField(controller: originalNameController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Original filename')),
        const SizedBox(height: 12),
        TextField(controller: storagePathController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Storage path or object key')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: contentType, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Content type'), items: const [DropdownMenuItem(value: 'image/jpeg', child: Text('JPEG')), DropdownMenuItem(value: 'image/png', child: Text('PNG')), DropdownMenuItem(value: 'image/webp', child: Text('WEBP')), DropdownMenuItem(value: 'application/pdf', child: Text('PDF'))], onChanged: (value) => setState(() => contentType = value ?? 'image/jpeg')),
        const SizedBox(height: 12),
        TextField(controller: sizeController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Size bytes')),
        const SizedBox(height: 16),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (error != null) const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : _save, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save file record')),
      ]),
    );
  }

  Future<void> _save() async {
    final originalName = originalNameController.text.trim();
    final storagePath = storagePathController.text.trim();
    final size = int.tryParse(sizeController.text.trim());
    if (originalName.isEmpty || storagePath.isEmpty || size == null || size < 0) {
      setState(() => error = 'Enter filename, storage path and valid size');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.createMetadata(projectId: widget.projectId, kind: kind, originalName: originalName, storagePath: storagePath, contentType: contentType, sizeBytes: size);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class BackendExpenseFormScreenV2 extends StatefulWidget {
  const BackendExpenseFormScreenV2({required this.projectId, required this.repository, super.key});
  final String projectId;
  final CostItemRepository repository;
  @override
  State<BackendExpenseFormScreenV2> createState() => _BackendExpenseFormScreenV2State();
}

class _BackendExpenseFormScreenV2State extends State<BackendExpenseFormScreenV2> {
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  final categoryController = TextEditingController(text: 'materials');
  final vendorController = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() { titleController.dispose(); amountController.dispose(); categoryController.dispose(); vendorController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => _SimpleFormScaffold(title: 'Add expense', error: error, busy: busy, buttonText: 'Save expense', onSave: _save, children: [TextField(controller: titleController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Title')), const SizedBox(height: 12), TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Amount, KGS')), const SizedBox(height: 12), TextField(controller: categoryController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Category')), const SizedBox(height: 12), TextField(controller: vendorController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Vendor'))]);
  Future<void> _save() async { final title = titleController.text.trim(); final amount = double.tryParse(amountController.text.trim()); if (title.isEmpty || amount == null || amount < 0) { setState(() => error = 'Enter valid title and amount'); return; } setState(() { busy = true; error = null; }); try { await widget.repository.create(projectId: widget.projectId, title: title, amount: amount, category: categoryController.text.trim(), vendor: vendorController.text.trim()); if (mounted) Navigator.of(context).pop(true); } catch (e) { setState(() => error = _friendlyError(e)); } finally { if (mounted) setState(() => busy = false); } }
}

class BackendReportFormScreenV2 extends StatefulWidget { const BackendReportFormScreenV2({required this.projectId, required this.repository, super.key}); final String projectId; final DailyReportRepository repository; @override State<BackendReportFormScreenV2> createState() => _BackendReportFormScreenV2State(); }
class _BackendReportFormScreenV2State extends State<BackendReportFormScreenV2> { final summaryController = TextEditingController(); final workersController = TextEditingController(text: '1'); final issuesController = TextEditingController(); bool busy = false; String? error; @override void dispose() { summaryController.dispose(); workersController.dispose(); issuesController.dispose(); super.dispose(); } @override Widget build(BuildContext context) => _SimpleFormScaffold(title: 'Add report', error: error, busy: busy, buttonText: 'Save report', onSave: _save, children: [TextField(controller: summaryController, minLines: 3, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Work summary')), const SizedBox(height: 12), TextField(controller: workersController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Workers count')), const SizedBox(height: 12), TextField(controller: issuesController, minLines: 2, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Issues / delays'))]); Future<void> _save() async { final summary = summaryController.text.trim(); final workers = int.tryParse(workersController.text.trim()); if (summary.isEmpty || workers == null || workers < 0) { setState(() => error = 'Enter valid summary and workers count'); return; } setState(() { busy = true; error = null; }); try { await widget.repository.create(projectId: widget.projectId, summary: summary, workersCount: workers, issues: issuesController.text.trim()); if (mounted) Navigator.of(context).pop(true); } catch (e) { setState(() => error = _friendlyError(e)); } finally { if (mounted) setState(() => busy = false); } } }

class BackendTaskFormScreenV2 extends StatefulWidget { const BackendTaskFormScreenV2({required this.projectId, required this.repository, super.key}); final String projectId; final TaskRepository repository; @override State<BackendTaskFormScreenV2> createState() => _BackendTaskFormScreenV2State(); }
class _BackendTaskFormScreenV2State extends State<BackendTaskFormScreenV2> { final titleController = TextEditingController(); final descriptionController = TextEditingController(); bool busy = false; String? error; @override void dispose() { titleController.dispose(); descriptionController.dispose(); super.dispose(); } @override Widget build(BuildContext context) => _SimpleFormScaffold(title: 'Add task', error: error, busy: busy, buttonText: 'Save task', onSave: _save, children: [TextField(controller: titleController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Title')), const SizedBox(height: 12), TextField(controller: descriptionController, minLines: 3, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Description'))]); Future<void> _save() async { final title = titleController.text.trim(); if (title.isEmpty) { setState(() => error = 'Task title is required'); return; } setState(() { busy = true; error = null; }); try { await widget.repository.create(projectId: widget.projectId, title: title, description: descriptionController.text.trim()); if (mounted) Navigator.of(context).pop(true); } catch (e) { setState(() => error = _friendlyError(e)); } finally { if (mounted) setState(() => busy = false); } } }

class _SimpleFormScaffold extends StatelessWidget { const _SimpleFormScaffold({required this.title, required this.children, required this.error, required this.busy, required this.buttonText, required this.onSave}); final String title; final List<Widget> children; final String? error; final bool busy; final String buttonText; final VoidCallback onSave; @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: ListView(padding: const EdgeInsets.all(16), children: [...children, const SizedBox(height: 16), if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), if (error != null) const SizedBox(height: 12), FilledButton(onPressed: busy ? null : onSave, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(buttonText))])); }

class BackendExpenseTileV2 extends StatelessWidget { const BackendExpenseTileV2({required this.item, super.key}); final RemoteCostItem item; @override Widget build(BuildContext context) { final vendor = item.vendor.isEmpty ? '' : ' • ${item.vendor}'; return Card(child: ListTile(leading: const Icon(Icons.receipt_long), title: Text(item.title), subtitle: Text('${item.category}$vendor'), trailing: Text('${item.amount.toStringAsFixed(0)} ${item.currency}'))); } }
class BackendReportTileV2 extends StatelessWidget { const BackendReportTileV2({required this.item, super.key}); final RemoteDailyReport item; @override Widget build(BuildContext context) { final issues = item.issues.isEmpty ? '' : ' • Issues: ${item.issues}'; return Card(child: ListTile(leading: const Icon(Icons.assignment), title: Text(item.summary), subtitle: Text('${item.workersCount} workers$issues'))); } }
class BackendTaskTileV2 extends StatelessWidget { const BackendTaskTileV2({required this.item, required this.onDone, super.key}); final RemoteTask item; final VoidCallback onDone; @override Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(item.status == 'done' ? Icons.check_circle : Icons.radio_button_unchecked), title: Text(item.title), subtitle: Text(item.description.isEmpty ? item.status : '${item.description} • ${item.status}'), trailing: item.status == 'done' ? null : TextButton(onPressed: onDone, child: const Text('Done')))); }
class BackendFileTileV2 extends StatelessWidget { const BackendFileTileV2({required this.item, super.key}); final RemoteProjectFile item; @override Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(item.contentType.startsWith('image/') ? Icons.image : Icons.picture_as_pdf), title: Text(item.originalName), subtitle: Text('${item.kind} • ${item.contentType} • ${item.sizeBytes} bytes'), trailing: const Icon(Icons.attach_file))); }
class DashboardSummaryCardV2 extends StatelessWidget { const DashboardSummaryCardV2({required this.title, required this.value, super.key}); final String title; final String value; @override Widget build(BuildContext context) => SizedBox(width: 160, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 8), Text(value, style: Theme.of(context).textTheme.headlineSmall)])))); }
class DashboardSectionHeaderV2 extends StatelessWidget { const DashboardSectionHeaderV2({required this.title, required this.count, super.key}); final String title; final int count; @override Widget build(BuildContext context) => Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)), Text('$count total', style: Theme.of(context).textTheme.bodySmall)]); }
class DashboardEmptyLineV2 extends StatelessWidget { const DashboardEmptyLineV2(this.message, {super.key}); final String message; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(message, style: Theme.of(context).textTheme.bodyMedium)); }
class BackendDashboardErrorV2 extends StatelessWidget { const BackendDashboardErrorV2({required this.message, required this.onRetry, super.key}); final String message; final VoidCallback onRetry; @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 56), const SizedBox(height: 16), Text('Could not load dashboard', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry'))]))); }
void _showMessage(BuildContext context, String message) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
String _friendlyError(Object? error) { final text = error.toString(); if (text.contains('408') || text.contains('timed out')) return 'Server timeout. Check internet or backend status.'; if (text.contains('401')) return 'Session expired. Please sign in again.'; if (text.contains('Connection refused') || text.contains('ApiException(0)')) return 'Cannot connect to backend. Check API_BASE_URL and server status.'; if (text.contains('invalid JSON')) return 'Backend returned an invalid response.'; return text.replaceFirst('Exception: ', ''); }
