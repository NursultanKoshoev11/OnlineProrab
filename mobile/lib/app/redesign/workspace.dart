part of '../online_prorab_redesign.dart';

class _ProjectWorkspace extends StatefulWidget {
  const _ProjectWorkspace({required this.project, required this.deps});

  final RemoteProject project;
  final _Dependencies deps;

  @override
  State<_ProjectWorkspace> createState() => _ProjectWorkspaceState();
}

class _ProjectWorkspaceState extends State<_ProjectWorkspace> {
  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<RemoteCostItem> _costs = const [];
  List<RemoteTask> _tasks = const [];
  List<RemoteDailyReport> _reports = const [];
  List<RemoteProjectFile> _files = const [];
  List<RemoteProjectMember> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.deps.costItemRepository.list(widget.project.id),
        widget.deps.taskRepository.list(widget.project.id),
        widget.deps.dailyReportRepository.list(widget.project.id),
        widget.deps.fileRepository.list(widget.project.id),
        widget.deps.teamRepository.listMembers(widget.project.id),
      ]);
      if (!mounted) return;
      setState(() {
        _costs = results[0] as List<RemoteCostItem>;
        _tasks = results[1] as List<RemoteTask>;
        _reports = results[2] as List<RemoteDailyReport>;
        _files = results[3] as List<RemoteProjectFile>;
        _members = results[4] as List<RemoteProjectMember>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.project.name.isEmpty ? 'Объект' : widget.project.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          IconButton(
            onPressed: () => _toast(context, 'Настройки объекта'),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _error != null
              ? _ErrorView(message: _error!, retry: _load)
              : IndexedStack(
                  index: _tab,
                  children: [
                    _OverviewTab(
                      project: widget.project,
                      costs: _costs,
                      tasks: _tasks,
                      files: _files,
                      members: _members,
                      openTab: (index) => setState(() => _tab = index),
                    ),
                    _ExpensesTab(
                      project: widget.project,
                      repository: widget.deps.costItemRepository,
                      initial: _costs,
                      onChanged: (items) => setState(() => _costs = items),
                    ),
                    _TasksTab(
                      project: widget.project,
                      repository: widget.deps.taskRepository,
                      initial: _tasks,
                      onChanged: (items) => setState(() => _tasks = items),
                    ),
                    _MoreTab(
                      project: widget.project,
                      reports: _reports,
                      files: _files,
                      members: _members,
                      costs: _costs,
                    ),
                  ],
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
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
            icon: Icon(Icons.more_horiz_rounded),
            label: 'Ещё',
          ),
        ],
      ),
    );
  }
}
