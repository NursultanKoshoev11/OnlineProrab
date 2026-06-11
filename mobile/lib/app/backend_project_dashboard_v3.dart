import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/services/project_file_download_service.dart';
import 'package:path_provider/path_provider.dart';

class BackendProjectDashboardScreenV3 extends StatefulWidget {
  const BackendProjectDashboardScreenV3({
    required this.project,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    required this.fileRepository,
    required this.fileDownloadService,
    super.key,
  });

  final RemoteProject project;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  final ProjectFileDownloadService fileDownloadService;

  @override
  State<BackendProjectDashboardScreenV3> createState() =>
      _BackendProjectDashboardScreenV3State();
}

class _BackendProjectDashboardScreenV3State
    extends State<BackendProjectDashboardScreenV3> {
  late Future<ProjectDashboardDataV3> dashboardFuture;

  @override
  void initState() {
    super.initState();
    dashboardFuture = _load();
  }

  Future<ProjectDashboardDataV3> _load() async {
    final results = await Future.wait<dynamic>([
      widget.costItemRepository.list(widget.project.id),
      widget.dailyReportRepository.list(widget.project.id),
      widget.taskRepository.list(widget.project.id),
      widget.fileRepository.list(widget.project.id),
    ]);
    return ProjectDashboardDataV3(
      expenses: results[0] as List<RemoteCostItem>,
      reports: results[1] as List<RemoteDailyReport>,
      tasks: results[2] as List<RemoteTask>,
      files: results[3] as List<RemoteProjectFile>,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => dashboardFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name.isEmpty ? 'Project' : widget.project.name),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<ProjectDashboardDataV3>(
        future: dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _DashboardError(
              message: _friendlyError(snapshot.error),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data ??
              const ProjectDashboardDataV3(
                expenses: [],
                reports: [],
                tasks: [],
                files: [],
              );
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.project.address.isEmpty
                      ? 'No address'
                      : widget.project.address,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryCard(
                      title: 'Total spent',
                      value: '${data.totalSpent.toStringAsFixed(0)} KGS',
                    ),
                    _SummaryCard(
                      title: 'Reports',
                      value: '${data.reports.length}',
                    ),
                    _SummaryCard(
                      title: 'Open tasks',
                      value: '${data.openTasksCount}',
                    ),
                    _SummaryCard(
                      title: 'Files',
                      value: '${data.files.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _addExpense,
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Expense'),
                    ),
                    FilledButton.icon(
                      onPressed: _addReport,
                      icon: const Icon(Icons.assignment),
                      label: const Text('Report'),
                    ),
                    FilledButton.icon(
                      onPressed: _addTask,
                      icon: const Icon(Icons.task_alt),
                      label: const Text('Task'),
                    ),
                    FilledButton.icon(
                      onPressed: _addFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Upload file'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: 'Expenses', count: data.expenses.length),
                if (data.expenses.isEmpty)
                  const _EmptyLine('No expenses yet')
                else
                  ...data.expenses.map((item) => _ExpenseTile(item: item)),
                const SizedBox(height: 20),
                _SectionHeader(
                  title: 'Daily reports',
                  count: data.reports.length,
                ),
                if (data.reports.isEmpty)
                  const _EmptyLine('No reports yet')
                else
                  ...data.reports.map((item) => _ReportTile(item: item)),
                const SizedBox(height: 20),
                _SectionHeader(title: 'Tasks', count: data.tasks.length),
                if (data.tasks.isEmpty)
                  const _EmptyLine('No tasks yet')
                else
                  ...data.tasks.map(
                    (item) => _TaskTile(
                      item: item,
                      onDone: () => _markTaskDone(item),
                    ),
                  ),
                const SizedBox(height: 20),
                _SectionHeader(title: 'Files', count: data.files.length),
                if (data.files.isEmpty)
                  const _EmptyLine('No files yet')
                else
                  ...data.files.map(
                    (item) => _FileTile(
                      item: item,
                      onOpen: () => _openFile(item),
                      onDelete: () => _deleteFile(item),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addExpense() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreenV3(
          projectId: widget.project.id,
          repository: widget.costItemRepository,
        ),
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _addReport() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReportFormScreenV3(
          projectId: widget.project.id,
          repository: widget.dailyReportRepository,
        ),
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _addTask() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskFormScreenV3(
          projectId: widget.project.id,
          repository: widget.taskRepository,
        ),
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _addFile() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FileUploadScreenV3(
          projectId: widget.project.id,
          repository: widget.fileRepository,
        ),
      ),
    );
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

  Future<void> _openFile(RemoteProjectFile file) async {
    _showMessage(context, 'Downloading ${file.originalName}…');
    try {
      final downloaded = await widget.fileDownloadService.download(
        fileId: file.id,
        fallbackFileName: file.originalName,
        fallbackContentType: file.contentType,
      );
      if (!mounted) return;
      if (downloaded.isImage) {
        await showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            child: InteractiveViewer(
              child: Image.memory(downloaded.bytes, fit: BoxFit.contain),
            ),
          ),
        );
        return;
      }

      final directory = await getTemporaryDirectory();
      final safeName = _safeLocalFileName(downloaded.fileName);
      final target = File('${directory.path}/$safeName');
      await target.writeAsBytes(downloaded.bytes, flush: true);
      final result = await OpenFilex.open(target.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        _showMessage(context, result.message);
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(context, _friendlyError(error));
    }
  }

  Future<void> _deleteFile(RemoteProjectFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('Delete “${file.originalName}” from this project?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.fileRepository.delete(file.id);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      _showMessage(context, _friendlyError(error));
    }
  }
}

class ProjectDashboardDataV3 {
  const ProjectDashboardDataV3({
    required this.expenses,
    required this.reports,
    required this.tasks,
    required this.files,
  });

  final List<RemoteCostItem> expenses;
  final List<RemoteDailyReport> reports;
  final List<RemoteTask> tasks;
  final List<RemoteProjectFile> files;

  double get totalSpent =>
      expenses.fold<double>(0, (sum, item) => sum + item.amount);
  int get openTasksCount =>
      tasks.where((item) => item.status != 'done').length;
}

class FileUploadScreenV3 extends StatefulWidget {
  const FileUploadScreenV3({
    required this.projectId,
    required this.repository,
    super.key,
  });

  final String projectId;
  final ProjectFileRepository repository;

  @override
  State<FileUploadScreenV3> createState() => _FileUploadScreenV3State();
}

class _FileUploadScreenV3State extends State<FileUploadScreenV3> {
  String kind = 'receipt';
  PlatformFile? selectedFile;
  bool busy = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: kind,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Kind',
            ),
            items: const [
              DropdownMenuItem(value: 'receipt', child: Text('Receipt')),
              DropdownMenuItem(value: 'photo', child: Text('Photo')),
              DropdownMenuItem(value: 'document', child: Text('Document')),
            ],
            onChanged: busy
                ? null
                : (value) => setState(() => kind = value ?? 'document'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy ? null : _pickFile,
            icon: const Icon(Icons.folder_open),
            label: Text(
              selectedFile == null
                  ? 'Choose JPG, PNG, WEBP or PDF'
                  : selectedFile!.name,
            ),
          ),
          if (selectedFile != null) ...[
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(selectedFile!.size)} selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          if (error != null) ...[
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: busy || selectedFile == null ? null : _upload,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: Text(busy ? 'Uploading…' : 'Upload'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() => error = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.path == null || file.path!.isEmpty) {
        setState(() {
          selectedFile = null;
          error = 'The selected file is not available as a local file.';
        });
        return;
      }
      setState(() => selectedFile = file);
    } catch (pickerError) {
      if (!mounted) return;
      setState(() => error = _friendlyError(pickerError));
    }
  }

  Future<void> _upload() async {
    final file = selectedFile;
    final path = file?.path;
    if (file == null || path == null || path.isEmpty) {
      setState(() => error = 'Choose a file first.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.upload(
        projectId: widget.projectId,
        kind: kind,
        filePath: path,
        fileName: file.name,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (uploadError) {
      if (!mounted) return;
      setState(() => error = _friendlyError(uploadError));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class ExpenseFormScreenV3 extends StatefulWidget {
  const ExpenseFormScreenV3({
    required this.projectId,
    required this.repository,
    super.key,
  });

  final String projectId;
  final CostItemRepository repository;

  @override
  State<ExpenseFormScreenV3> createState() => _ExpenseFormScreenV3State();
}

class _ExpenseFormScreenV3State extends State<ExpenseFormScreenV3> {
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
  Widget build(BuildContext context) => _SimpleFormScaffold(
        title: 'Add expense',
        error: error,
        busy: busy,
        buttonText: 'Save expense',
        onSave: _save,
        children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Title',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Amount, KGS',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: categoryController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Category',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: vendorController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Vendor',
            ),
          ),
        ],
      );

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
      await widget.repository.create(
        projectId: widget.projectId,
        title: title,
        amount: amount,
        category: categoryController.text.trim(),
        vendor: vendorController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (saveError) {
      if (!mounted) return;
      setState(() => error = _friendlyError(saveError));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class ReportFormScreenV3 extends StatefulWidget {
  const ReportFormScreenV3({
    required this.projectId,
    required this.repository,
    super.key,
  });

  final String projectId;
  final DailyReportRepository repository;

  @override
  State<ReportFormScreenV3> createState() => _ReportFormScreenV3State();
}

class _ReportFormScreenV3State extends State<ReportFormScreenV3> {
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
  Widget build(BuildContext context) => _SimpleFormScaffold(
        title: 'Add report',
        error: error,
        busy: busy,
        buttonText: 'Save report',
        onSave: _save,
        children: [
          TextField(
            controller: summaryController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Work summary',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: workersController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Workers count',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: issuesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Issues / delays',
            ),
          ),
        ],
      );

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
      await widget.repository.create(
        projectId: widget.projectId,
        summary: summary,
        workersCount: workers,
        issues: issuesController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (saveError) {
      if (!mounted) return;
      setState(() => error = _friendlyError(saveError));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class TaskFormScreenV3 extends StatefulWidget {
  const TaskFormScreenV3({
    required this.projectId,
    required this.repository,
    super.key,
  });

  final String projectId;
  final TaskRepository repository;

  @override
  State<TaskFormScreenV3> createState() => _TaskFormScreenV3State();
}

class _TaskFormScreenV3State extends State<TaskFormScreenV3> {
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
  Widget build(BuildContext context) => _SimpleFormScaffold(
        title: 'Add task',
        error: error,
        busy: busy,
        buttonText: 'Save task',
        onSave: _save,
        children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Title',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descriptionController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Description',
            ),
          ),
        ],
      );

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
      await widget.repository.create(
        projectId: widget.projectId,
        title: title,
        description: descriptionController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (saveError) {
      if (!mounted) return;
      setState(() => error = _friendlyError(saveError));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _SimpleFormScaffold extends StatelessWidget {
  const _SimpleFormScaffold({
    required this.title,
    required this.children,
    required this.error,
    required this.busy,
    required this.buttonText,
    required this.onSave,
  });

  final String title;
  final List<Widget> children;
  final String? error;
  final bool busy;
  final String buttonText;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...children,
          const SizedBox(height: 16),
          if (error != null) ...[
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: busy ? null : onSave,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(buttonText),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.item});

  final RemoteCostItem item;

  @override
  Widget build(BuildContext context) {
    final vendor = item.vendor.isEmpty ? '' : ' • ${item.vendor}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long),
        title: Text(item.title),
        subtitle: Text('${item.category}$vendor'),
        trailing: Text('${item.amount.toStringAsFixed(0)} ${item.currency}'),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.item});

  final RemoteDailyReport item;

  @override
  Widget build(BuildContext context) {
    final issues = item.issues.isEmpty ? '' : ' • Issues: ${item.issues}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.assignment),
        title: Text(item.summary),
        subtitle: Text('${item.workersCount} workers$issues'),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.item, required this.onDone});

  final RemoteTask item;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          item.status == 'done'
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
        ),
        title: Text(item.title),
        subtitle: Text(
          item.description.isEmpty
              ? item.status
              : '${item.description} • ${item.status}',
        ),
        trailing: item.status == 'done'
            ? null
            : TextButton(onPressed: onDone, child: const Text('Done')),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.item,
    required this.onOpen,
    required this.onDelete,
  });

  final RemoteProjectFile item;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          item.contentType.startsWith('image/')
              ? Icons.image
              : Icons.picture_as_pdf,
        ),
        title: Text(item.originalName),
        subtitle: Text(
          '${item.kind} • ${item.contentType} • ${_formatBytes(item.sizeBytes)}',
        ),
        onTap: onOpen,
        trailing: IconButton(
          tooltip: 'Delete file',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value});

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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text('$count total', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56),
            const SizedBox(height: 16),
            Text(
              'Could not load dashboard',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _friendlyError(Object? error) {
  final text = error.toString();
  if (text.contains('408') || text.contains('timed out')) {
    return 'Server timeout. Check internet or backend status.';
  }
  if (text.contains('401')) return 'Session expired. Please sign in again.';
  if (text.contains('Connection refused') || text.contains('ApiException(0)')) {
    return 'Cannot connect to backend. Check API_BASE_URL and server status.';
  }
  if (text.contains('invalid JSON')) {
    return 'Backend returned an invalid response.';
  }
  return text.replaceFirst('Exception: ', '');
}

String _safeLocalFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll('..', '_')
      .trim();
  return cleaned.isEmpty ? 'download' : cleaned;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  final megabytes = kilobytes / 1024;
  return '${megabytes.toStringAsFixed(1)} MB';
}
