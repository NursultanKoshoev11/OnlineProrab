import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:online_prorab/app/online_prorab_theme.dart';
import 'package:online_prorab/app/project_team_screen.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/features/projects/project_team_repository.dart';
import 'package:online_prorab/services/project_file_download_service.dart';
import 'package:path_provider/path_provider.dart';

class BackendProjectDashboardScreenV3 extends StatefulWidget {
  const BackendProjectDashboardScreenV3({
    required this.project,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    required this.fileRepository,
    required this.teamRepository,
    required this.fileDownloadService,
    super.key,
  });

  final RemoteProject project;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;
  final ProjectFileDownloadService fileDownloadService;

  @override
  State<BackendProjectDashboardScreenV3> createState() =>
      _BackendProjectDashboardScreenV3State();
}

class _BackendProjectDashboardScreenV3State
    extends State<BackendProjectDashboardScreenV3> {
  late Future<ProjectDashboardDataV3> _dashboardFuture;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _load();
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
    setState(() => _dashboardFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.project.name.isEmpty ? 'Объект' : widget.project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (widget.project.address.isNotEmpty)
              Text(
                widget.project.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: OnlineProrabColors.textMuted,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<ProjectDashboardDataV3>(
        future: _dashboardFuture,
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

          final data = snapshot.data ?? ProjectDashboardDataV3.empty();
          final page = switch (_tab) {
            0 => _OverviewTab(
                project: widget.project,
                data: data,
                onAddExpense: _addExpense,
                onAddTask: _addTask,
                onAddReport: _addReport,
                onOpenExpenses: () => setState(() => _tab = 1),
                onOpenTasks: () => setState(() => _tab = 2),
              ),
            1 => _ExpensesTab(
                data: data,
                onVoiceSearch: _askExpenseQuery,
                onAdd: _addExpense,
              ),
            2 => _TasksTab(
                tasks: data.tasks,
                onAdd: _addTask,
                onDone: _markTaskDone,
              ),
            3 => _ReportsTab(reports: data.reports, onAdd: _addReport),
            _ => _MoreTab(
                files: data.files,
                onAddFile: _addFile,
                onOpenFile: _openFile,
                onDeleteFile: _deleteFile,
                onOpenTeam: _openTeam,
              ),
          };

          return RefreshIndicator(onRefresh: _refresh, child: page);
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Обзор',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Расходы',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            selectedIcon: Icon(Icons.task_alt_rounded),
            label: 'Задачи',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Отчёты',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            label: 'Ещё',
          ),
        ],
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

  void _openTeam() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectTeamScreen(
          projectId: widget.project.id,
          repository: widget.teamRepository,
        ),
      ),
    );
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

  Future<String?> _askExpenseQuery() async {
    final controller = TextEditingController();
    final query = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OnlineProrabColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          MediaQuery.of(sheetContext).viewInsets.bottom + 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: OnlineProrabColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: OnlineProrabColors.mint,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.mic_none_rounded,
                    color: OnlineProrabColors.primary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI-поиск расходов',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Ищет только по данным этого объекта',
                        style: TextStyle(
                          color: OnlineProrabColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Например: сколько потратили на окна?',
                prefixIcon: Icon(Icons.auto_awesome_outlined),
              ),
              onSubmitted: (value) => Navigator.of(sheetContext).pop(value),
            ),
            const SizedBox(height: 12),
            const Text(
              'Распознавание речи с микрофона будет подключено отдельно. Сейчас запрос можно ввести текстом; сумма всегда считается из реальных расходов backend.',
              style: TextStyle(
                color: OnlineProrabColors.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(controller.text.trim()),
                icon: const Icon(Icons.search_rounded),
                label: const Text('Найти'),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return query?.trim();
  }

  Future<void> _openFile(RemoteProjectFile file) async {
    _showMessage(context, 'Загружаем ${file.originalName}…');
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
      final target = File(
        '${directory.path}/${_safeLocalFileName(downloaded.fileName)}',
      );
      await target.writeAsBytes(downloaded.bytes, flush: true);
      final result = await OpenFilex.open(target.path);
      if (!mounted) return;
      if (result.type != ResultType.done) _showMessage(context, result.message);
    } catch (error) {
      if (!mounted) return;
      _showMessage(context, _friendlyError(error));
    }
  }

  Future<void> _deleteFile(RemoteProjectFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text('Файл «${file.originalName}» будет удалён из объекта.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
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

  factory ProjectDashboardDataV3.empty() => const ProjectDashboardDataV3(
        expenses: [],
        reports: [],
        tasks: [],
        files: [],
      );

  final List<RemoteCostItem> expenses;
  final List<RemoteDailyReport> reports;
  final List<RemoteTask> tasks;
  final List<RemoteProjectFile> files;

  double get totalSpent =>
      expenses.fold<double>(0, (sum, item) => sum + item.amount);

  int get openTasksCount =>
      tasks.where((item) => item.status.toLowerCase() != 'done').length;
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.project,
    required this.data,
    required this.onAddExpense,
    required this.onAddTask,
    required this.onAddReport,
    required this.onOpenExpenses,
    required this.onOpenTasks,
  });

  final RemoteProject project;
  final ProjectDashboardDataV3 data;
  final VoidCallback onAddExpense;
  final VoidCallback onAddTask;
  final VoidCallback onAddReport;
  final VoidCallback onOpenExpenses;
  final VoidCallback onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final recentExpenses = data.expenses.take(3).toList();
    final openTasks = data.tasks
        .where((item) => item.status.toLowerCase() != 'done')
        .take(3)
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE0EAE4), Color(0xFFC4D6CC)],
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: OnlineProrabColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusLabel(project.status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.apartment_rounded,
                    color: Color(0x88315F4D),
                    size: 54,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                project.name.isEmpty ? 'Объект' : project.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (project.address.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: OnlineProrabColors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        project.address,
                        style: const TextStyle(
                          color: OnlineProrabColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('Сводка', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Потрачено',
                value: _money(data.totalSpent),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                icon: Icons.task_alt_rounded,
                label: 'Открытые задачи',
                value: '${data.openTasksCount}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.assignment_outlined,
                label: 'Отчёты',
                value: '${data.reports.length}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                icon: Icons.folder_outlined,
                label: 'Файлы',
                value: '${data.files.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Быстрые действия',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.add_card_rounded,
                label: 'Расход',
                onTap: onAddExpense,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.add_task_rounded,
                label: 'Задача',
                onTap: onAddTask,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.note_add_outlined,
                label: 'Отчёт',
                onTap: onAddReport,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _SectionTitle(
          title: 'Последние расходы',
          action: 'Все',
          onAction: onOpenExpenses,
        ),
        const SizedBox(height: 10),
        if (recentExpenses.isEmpty)
          const _EmptyCard(
            icon: Icons.receipt_long_outlined,
            text: 'Расходов пока нет',
          )
        else
          ...recentExpenses.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _ExpenseCard(item: item),
            ),
          ),
        const SizedBox(height: 18),
        _SectionTitle(
          title: 'Ближайшие задачи',
          action: 'Все',
          onAction: onOpenTasks,
        ),
        const SizedBox(height: 10),
        if (openTasks.isEmpty)
          const _EmptyCard(
            icon: Icons.task_alt_outlined,
            text: 'Открытых задач нет',
          )
        else
          ...openTasks.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _TaskCard(item: item),
            ),
          ),
      ],
    );
  }
}

class _ExpensesTab extends StatefulWidget {
  const _ExpensesTab({
    required this.data,
    required this.onVoiceSearch,
    required this.onAdd,
  });

  final ProjectDashboardDataV3 data;
  final Future<String?> Function() onVoiceSearch;
  final VoidCallback onAdd;

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _searchExpenses(widget.data.expenses, _query);
    final filteredTotal =
        filtered.fold<double>(0, (sum, item) => sum + item.amount);
    final searching = _query.trim().isNotEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Расходы',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.data.expenses.length} записей',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: OnlineProrabColors.primary,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                searching ? 'Найдено на сумму' : 'Всего потрачено',
                style: const TextStyle(
                  color: Color(0xFFD8E7DF),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _money(searching ? filteredTotal : widget.data.totalSpent),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Сколько потратили на окна?',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'AI-поиск',
              onPressed: _voiceSearch,
              icon: const Icon(
                Icons.mic_none_rounded,
                color: OnlineProrabColors.primary,
              ),
            ),
          ),
        ),
        if (searching) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: OnlineProrabColors.mint,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: OnlineProrabColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'По запросу «$_query» найдено: ${filtered.length}',
                    style: const TextStyle(
                      color: OnlineProrabColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          _EmptyCard(
            icon: Icons.search_off_rounded,
            text: searching
                ? 'По этому запросу расходов нет'
                : 'Расходов пока нет',
          )
        else
          ...filtered.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ExpenseCard(item: item),
            ),
          ),
      ],
    );
  }

  Future<void> _voiceSearch() async {
    final result = await widget.onVoiceSearch();
    if (!mounted || result == null || result.isEmpty) return;
    _controller.text = result;
    _controller.selection = TextSelection.collapsed(offset: result.length);
    setState(() => _query = result);
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({
    required this.tasks,
    required this.onAdd,
    required this.onDone,
  });

  final List<RemoteTask> tasks;
  final VoidCallback onAdd;
  final ValueChanged<RemoteTask> onDone;

  @override
  Widget build(BuildContext context) {
    final open =
        tasks.where((item) => item.status.toLowerCase() != 'done').toList();
    final done =
        tasks.where((item) => item.status.toLowerCase() == 'done').toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _PageHeader(
          title: 'Задачи',
          subtitle: '${open.length} в работе',
          buttonLabel: 'Задача',
          onAdd: onAdd,
        ),
        const SizedBox(height: 22),
        Text('В работе', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (open.isEmpty)
          const _EmptyCard(
            icon: Icons.task_alt_rounded,
            text: 'Все задачи выполнены',
          )
        else
          ...open.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskCard(item: item, onDone: () => onDone(item)),
            ),
          ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Готово', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ...done.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskCard(item: item),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({required this.reports, required this.onAdd});

  final List<RemoteDailyReport> reports;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _PageHeader(
          title: 'Отчёты',
          subtitle: '${reports.length} записей',
          buttonLabel: 'Отчёт',
          onAdd: onAdd,
        ),
        const SizedBox(height: 22),
        if (reports.isEmpty)
          const _EmptyCard(
            icon: Icons.assignment_outlined,
            text: 'Отчётов пока нет',
          )
        else
          ...reports.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReportCard(item: item),
            ),
          ),
      ],
    );
  }
}

class _MoreTab extends StatelessWidget {
  const _MoreTab({
    required this.files,
    required this.onAddFile,
    required this.onOpenFile,
    required this.onDeleteFile,
    required this.onOpenTeam,
  });

  final List<RemoteProjectFile> files;
  final VoidCallback onAddFile;
  final ValueChanged<RemoteProjectFile> onOpenFile;
  final ValueChanged<RemoteProjectFile> onDeleteFile;
  final VoidCallback onOpenTeam;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text('Ещё', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 18),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const _RoundIcon(icon: Icons.groups_2_outlined),
                title: const Text(
                  'Команда',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Участники и роли проекта'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onOpenTeam,
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: const _RoundIcon(
                  icon: Icons.add_photo_alternate_outlined,
                ),
                title: const Text(
                  'Добавить файл',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Фото, чек или документ'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onAddFile,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: 'Файлы',
          action: '${files.length}',
          onAction: null,
        ),
        const SizedBox(height: 10),
        if (files.isEmpty)
          const _EmptyCard(
            icon: Icons.folder_outlined,
            text: 'Файлов пока нет',
          )
        else
          ...files.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FileCard(
                item: item,
                onOpen: () => onOpenFile(item),
                onDelete: () => onDeleteFile(item),
              ),
            ),
          ),
      ],
    );
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
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _category = TextEditingController(text: 'materials');
  final _vendor = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _category.dispose();
    _vendor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SimpleFormScaffold(
        title: 'Новый расход',
        intro: 'Добавьте фактический расход по этому объекту.',
        error: _error,
        busy: _busy,
        buttonText: 'Сохранить расход',
        onSave: _save,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Название',
              prefixIcon: Icon(Icons.receipt_long_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Сумма, сом',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _category,
            decoration: const InputDecoration(
              labelText: 'Категория',
              prefixIcon: Icon(Icons.category_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _vendor,
            decoration: const InputDecoration(
              labelText: 'Поставщик',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
        ],
      );

  Future<void> _save() async {
    final title = _title.text.trim();
    final amount = double.tryParse(_amount.text.trim());
    if (title.isEmpty || amount == null || amount <= 0) {
      setState(() => _error = 'Введите корректное название и сумму.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.create(
        projectId: widget.projectId,
        title: title,
        amount: amount,
        category: _category.text.trim(),
        vendor: _vendor.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
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
  final _summary = TextEditingController();
  final _workers = TextEditingController(text: '1');
  final _issues = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _summary.dispose();
    _workers.dispose();
    _issues.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SimpleFormScaffold(
        title: 'Новый отчёт',
        intro: 'Зафиксируйте, что было сделано на объекте.',
        error: _error,
        busy: _busy,
        buttonText: 'Сохранить отчёт',
        onSave: _save,
        children: [
          TextField(
            controller: _summary,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Что сделали'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _workers,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Количество рабочих',
              prefixIcon: Icon(Icons.groups_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _issues,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Проблемы или задержки',
            ),
          ),
        ],
      );

  Future<void> _save() async {
    final summary = _summary.text.trim();
    final workers = int.tryParse(_workers.text.trim());
    if (summary.isEmpty || workers == null || workers < 0) {
      setState(() => _error = 'Заполните описание и количество рабочих.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.create(
        projectId: widget.projectId,
        summary: summary,
        workersCount: workers,
        issues: _issues.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
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
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SimpleFormScaffold(
        title: 'Новая задача',
        intro: 'Добавьте конкретную задачу для объекта.',
        error: _error,
        busy: _busy,
        buttonText: 'Сохранить задачу',
        onSave: _save,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Название задачи',
              prefixIcon: Icon(Icons.task_alt_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
        ],
      );

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Введите название задачи.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.create(
        projectId: widget.projectId,
        title: title,
        description: _description.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
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
  String _kind = 'receipt';
  PlatformFile? _selectedFile;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить файл')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            'Файл проекта',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Добавьте чек, фотографию или документ к этому объекту.',
            style: TextStyle(color: OnlineProrabColors.textMuted),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Тип файла'),
            items: const [
              DropdownMenuItem(value: 'receipt', child: Text('Чек')),
              DropdownMenuItem(value: 'photo', child: Text('Фото')),
              DropdownMenuItem(value: 'document', child: Text('Документ')),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _kind = value ?? 'document'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(
              _selectedFile == null
                  ? 'Выбрать JPG, PNG, WEBP или PDF'
                  : _selectedFile!.name,
            ),
          ),
          if (_selectedFile != null) ...[
            const SizedBox(height: 8),
            Text(
              _formatBytes(_selectedFile!.size),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            _FormError(message: _error!),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy || _selectedFile == null ? null : _upload,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_busy ? 'Загрузка…' : 'Загрузить'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.path == null || file.path!.isEmpty) {
        setState(() {
          _selectedFile = null;
          _error = 'Выбранный файл недоступен как локальный файл.';
        });
        return;
      }
      setState(() => _selectedFile = file);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _upload() async {
    final file = _selectedFile;
    final path = file?.path;
    if (file == null || path == null || path.isEmpty) {
      setState(() => _error = 'Сначала выберите файл.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.upload(
        projectId: widget.projectId,
        kind: _kind,
        filePath: path,
        fileName: file.name,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SimpleFormScaffold extends StatelessWidget {
  const _SimpleFormScaffold({
    required this.title,
    required this.intro,
    required this.children,
    required this.error,
    required this.busy,
    required this.buttonText,
    required this.onSave,
  });

  final String title;
  final String intro;
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 7),
          Text(
            intro,
            style: const TextStyle(color: OnlineProrabColors.textMuted),
          ),
          const SizedBox(height: 24),
          ...children,
          if (error != null) ...[
            const SizedBox(height: 14),
            _FormError(message: error!),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : onSave,
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(buttonText),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OnlineProrabColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OnlineProrabColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: OnlineProrabColors.primary),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
          ),
          const SizedBox(height: 3),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: OnlineProrabColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: OnlineProrabColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: OnlineProrabColors.mint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: OnlineProrabColors.primary, size: 20),
            ),
            const SizedBox(height: 9),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.item});

  final RemoteCostItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const _RoundIcon(icon: Icons.receipt_long_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? 'Расход' : item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [item.category, item.vendor]
                        .where((value) => value.trim().isNotEmpty)
                        .join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_formatNumber(item.amount)} ${_currencyLabel(item.currency)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.item, this.onDone});

  final RemoteTask item;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final done = item.status.toLowerCase() == 'done';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: done
                ? OnlineProrabColors.mint
                : OnlineProrabColors.surfaceSoft,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            done ? Icons.check_rounded : Icons.radio_button_unchecked_rounded,
            color: OnlineProrabColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: done ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: item.description.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        trailing: done || onDone == null
            ? null
            : IconButton(
                tooltip: 'Готово',
                onPressed: onDone,
                icon: const Icon(Icons.check_circle_outline_rounded),
              ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.item});

  final RemoteDailyReport item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _RoundIcon(icon: Icons.assignment_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.summary,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${item.workersCount} рабочих${item.issues.isEmpty ? '' : ' • Есть замечания'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.issues.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: OnlineProrabColors.warningSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.issues,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.item,
    required this.onOpen,
    required this.onDelete,
  });

  final RemoteProjectFile item;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final image = item.contentType.startsWith('image/');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        leading: _RoundIcon(
          icon: image ? Icons.image_outlined : Icons.description_outlined,
        ),
        title: Text(
          item.originalName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_fileKindLabel(item.kind)} • ${_formatBytes(item.sizeBytes)}',
        ),
        onTap: onOpen,
        trailing: IconButton(
          tooltip: 'Удалить',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: OnlineProrabColors.mint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: OnlineProrabColors.primary, size: 21),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (onAction != null)
          TextButton(onPressed: onAction, child: Text(action))
        else
          Text(
            action,
            style: const TextStyle(color: OnlineProrabColors.textMuted),
          ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(buttonLabel),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      decoration: BoxDecoration(
        color: OnlineProrabColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OnlineProrabColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: OnlineProrabColors.textMuted),
          const SizedBox(height: 10),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FormError extends StatelessWidget {
  const _FormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECE9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: OnlineProrabColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Не удалось загрузить объект',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

List<RemoteCostItem> _searchExpenses(
  List<RemoteCostItem> expenses,
  String rawQuery,
) {
  final query = rawQuery.toLowerCase().trim();
  if (query.isEmpty) return expenses;

  const stopWords = <String>{
    'сколько',
    'было',
    'потрачено',
    'потратили',
    'покажи',
    'показать',
    'найди',
    'найти',
    'расход',
    'расходы',
    'расходов',
    'сумма',
    'сумму',
    'на',
    'за',
    'по',
    'в',
    'во',
    'и',
    'всего',
    'мы',
    'я',
    'для',
  };

  final tokens = query
      .replaceAll(RegExp(r'[^a-zа-яё0-9\s-]'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.length > 1 && !stopWords.contains(token))
      .toList();

  if (tokens.isEmpty) return expenses;

  return expenses.where((item) {
    final haystack =
        '${item.title} ${item.category} ${item.vendor}'.toLowerCase();
    return tokens.every(haystack.contains);
  }).toList();
}

String _money(double amount) => '${_formatNumber(amount)} сом';

String _formatNumber(double value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < rounded.length; i++) {
    if (i > 0 && (rounded.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(rounded[i]);
  }
  return buffer.toString();
}

String _currencyLabel(String value) {
  final currency = value.toUpperCase();
  return currency == 'KGS' ? 'сом' : currency;
}

String _statusLabel(String status) {
  final value = status.toLowerCase();
  if (value == 'completed' || value == 'done') return 'Завершён';
  if (value == 'paused') return 'Приостановлен';
  return 'В работе';
}

String _fileKindLabel(String kind) {
  switch (kind.toLowerCase()) {
    case 'receipt':
      return 'Чек';
    case 'photo':
      return 'Фото';
    case 'document':
      return 'Документ';
    default:
      return kind;
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _friendlyError(Object? error) {
  final text = error.toString();
  if (text.contains('408') || text.toLowerCase().contains('timed out')) {
    return 'Сервер не ответил вовремя. Проверьте интернет и повторите.';
  }
  if (text.contains('401')) return 'Сессия истекла. Войдите снова.';
  if (text.contains('Connection refused') || text.contains('ApiException(0)')) {
    return 'Не удалось подключиться к серверу.';
  }
  if (text.contains('invalid JSON')) {
    return 'Сервер вернул некорректный ответ.';
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
