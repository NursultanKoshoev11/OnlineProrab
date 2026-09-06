part of '../online_prorab_redesign.dart';

class _ProjectWorkspace extends StatefulWidget {
  const _ProjectWorkspace({
    required this.project,
    required this.deps,
    required this.session,
  });

  final RemoteProject project;
  final _Dependencies deps;
  final SessionData session;

  @override
  State<_ProjectWorkspace> createState() => _ProjectWorkspaceState();
}

class _ProjectWorkspaceState extends State<_ProjectWorkspace> {
  int _tab = 0;
  int _loadGeneration = 0;
  bool _loading = true;
  List<String> _sectionErrors = const [];
  List<RemoteCostItem> _costs = const [];
  List<RemoteDailyReport> _reports = const [];
  List<RemoteProjectFile> _files = const [];
  List<RemoteProjectMember> _members = const [];
  List<RemoteAuditLog> _auditLogs = const [];

  String? get _currentRole {
    final projectRole = widget.project.role.trim().toLowerCase();
    if (projectRole.isNotEmpty) return projectRole;
    final phone = _normalizePhone(widget.session.phone);
    if (phone.isEmpty) return null;
    for (final member in _members) {
      if (_normalizePhone(member.phone) == phone) {
        return member.role.trim().toLowerCase();
      }
    }
    return null;
  }

  bool get _archived => widget.project.status.toLowerCase() == 'archived';

  bool get _canContribute =>
      !_archived &&
      const {'owner', 'manager', 'worker'}.contains(_currentRole);

  bool get _canManage =>
      !_archived &&
      const {'owner', 'manager'}.contains(_currentRole);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final generation = ++_loadGeneration;

    final costs = List<RemoteCostItem>.of(_costs);
    final reports = List<RemoteDailyReport>.of(_reports);
    final files = List<RemoteProjectFile>.of(_files);
    final members = List<RemoteProjectMember>.of(_members);
    final auditLogs = List<RemoteAuditLog>.of(_auditLogs);
    final errors = <String>[];
    final projectId = widget.project.id;

    await Future.wait<void>([
      _loadSection(
        label: 'Расходы',
        load: () => widget.deps.costItemRepository.list(projectId),
        assign: (value) {
          costs
            ..clear()
            ..addAll(value);
        },
        errors: errors,
      ),
      _loadSection(
        label: 'Отчёты',
        load: () => widget.deps.dailyReportRepository.list(projectId),
        assign: (value) {
          reports
            ..clear()
            ..addAll(value);
        },
        errors: errors,
      ),
      _loadSection(
        label: 'Файлы',
        load: () => widget.deps.fileRepository.list(projectId),
        assign: (value) {
          files
            ..clear()
            ..addAll(value);
        },
        errors: errors,
      ),
      _loadSection(
        label: 'Команда',
        load: () => widget.deps.teamRepository.listMembers(projectId),
        assign: (value) {
          members
            ..clear()
            ..addAll(value);
        },
        errors: errors,
      ),
      _loadSection(
        label: 'Журнал действий',
        load: () => widget.deps.auditLogRepository.list(projectId),
        assign: (value) {
          auditLogs
            ..clear()
            ..addAll(value);
        },
        errors: errors,
      ),
    ]);
    if (!mounted) return;
    if (generation != _loadGeneration) return;
    setState(() {
      _costs = costs;
      _reports = reports;
      _files = files;
      _members = members;
      _auditLogs = auditLogs;
      _sectionErrors = errors;
      _loading = false;
    });
  }

  Future<void> _loadSection<T>({
    required String label,
    required Future<T> Function() load,
    required void Function(T value) assign,
    required List<String> errors,
  }) async {
    try {
      assign(await load());
    } catch (error) {
      errors.add('$label: ${_errorText(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Обзор объекта',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Дополнительно',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'refresh') _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'refresh',
                child: Text('Обновить'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : Column(
              children: [
                if (_sectionErrors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _WorkspaceNotice(
                      errors: _sectionErrors,
                      onRetry: _load,
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _OverviewTab(
                        project: widget.project,
                        costs: _costs,
                        reports: _reports,
                        files: _files,
                        members: _members,
                        openTab: (index) => setState(() => _tab = index),
                      ),
                      _ExpensesTab(
                        project: widget.project,
                        repository: widget.deps.costItemRepository,
                        fileRepository: widget.deps.fileRepository,
                        onOpenFile: _openFile,
                        speechToText: widget.deps.speechToText,
                        initial: _costs,
                        onChanged: (items) => setState(() => _costs = items),
                        canContribute: _canContribute,
                        canManage: _canManage,
                      ),
                      _ReportsTab(
                        reports: _reports,
                        onAdd: _canContribute ? _addReport : null,
                        onDelete: _canManage ? _deleteReport : null,
                        onEdit: _canContribute ? _editReport : null,
                      ),
                      _MoreTab(
                        project: widget.project,
                        reports: _reports,
                        files: _files,
                        members: _members,
                        costs: _costs,
                        auditLogs: _auditLogs,
                        onOpenTeam: _openTeam,
                        onAddFile: _canContribute ? _addFile : null,
                        onOpenFile: _openFile,
                        onDeleteFile: _canManage ? _deleteFile : null,
                      ),
                    ],
                  ),
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

  Future<void> _addReport() async {
    final report = await Navigator.of(context).push<RemoteDailyReport>(
      MaterialPageRoute(
        builder: (_) => _ReportForm(
          projectId: widget.project.id,
          repository: widget.deps.dailyReportRepository,
        ),
      ),
    );
    if (!mounted || report == null) return;
    setState(() => _reports = [report, ..._reports]);
  }

  Future<void> _deleteReport(RemoteDailyReport report) async {
    final confirmed = await _confirmDelete(
      title: 'Удалить отчёт?',
      message: 'Этот ежедневный отчёт будет удалён из объекта.',
    );
    if (confirmed != true) return;
    try {
      await widget.deps.dailyReportRepository.delete(report.id);
      if (!mounted) return;
      setState(
        () => _reports = _reports.where((item) => item.id != report.id).toList(),
      );
      _toast(context, 'Отчёт удалён');
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    }
  }

  Future<void> _editReport(RemoteDailyReport report) async {
    final updated = await Navigator.of(context).push<RemoteDailyReport>(
      MaterialPageRoute(
        builder: (_) => _ReportForm(
          projectId: widget.project.id,
          repository: widget.deps.dailyReportRepository,
          initial: report,
        ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _reports = _reports
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
    });
  }

  Future<void> _openTeam() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectTeamScreen(
          projectId: widget.project.id,
          repository: widget.deps.teamRepository,
          canManage: _canManage,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _addFile() async {
    final file = await Navigator.of(context).push<RemoteProjectFile>(
      MaterialPageRoute(
        builder: (_) => _FileUploadForm(
          projectId: widget.project.id,
          repository: widget.deps.fileRepository,
        ),
      ),
    );
    if (!mounted || file == null) return;
    setState(() => _files = [file, ..._files]);
  }

  Future<void> _openFile(RemoteProjectFile file) async {
    final service = ProjectFileDownloadService(
      apiClient: widget.deps.apiClient,
      httpClient: widget.deps.offlineDemo
          ? widget.deps.apiClient.httpClient
          : null,
    );
    try {
      final downloaded = await service.download(
        fileId: file.id,
        fallbackFileName: file.originalName,
        fallbackContentType: file.contentType,
      );
      final directory = await getTemporaryDirectory();
      final safeName = _safeFileName(downloaded.fileName);
      final localFile = File('${directory.path}/$safeName');
      await localFile.writeAsBytes(downloaded.bytes, flush: true);
      await OpenFilex.open(localFile.path);
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    } finally {
      service.close();
    }
  }

  Future<void> _deleteFile(RemoteProjectFile file) async {
    final name = file.originalName.isEmpty ? 'этот файл' : file.originalName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text('$name будет удалён из объекта.'),
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
      await widget.deps.fileRepository.delete(file.id);
      if (!mounted) return;
      setState(
        () => _files = _files.where((item) => item.id != file.id).toList(),
      );
      _toast(context, 'Файл удалён');
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    }
  }

  String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return cleaned.isEmpty ? 'online_prorab_file' : cleaned;
  }

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
  }
}

class _WorkspaceNotice extends StatelessWidget {
  const _WorkspaceNotice({required this.errors, required this.onRetry});

  final List<String> errors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _warningSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.warning_amber_rounded, color: _warning),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Не удалось загрузить: ${errors.join('; ')}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _ink, fontSize: 12),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
