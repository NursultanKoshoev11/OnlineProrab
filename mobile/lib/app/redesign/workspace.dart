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
  List<RemoteProjectFile> _files = const [];
  List<RemoteProjectMember> _members = const [];
  RemoteProject? _project;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  Timer? _realtimeReloadDebounce;

  RemoteProject get _currentProject => _project ?? widget.project;

  String? get _currentRole {
    final projectRole = _currentProject.role.trim().toLowerCase();
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

  bool get _archived => _currentProject.status.toLowerCase() == 'archived';

  bool get _canContribute =>
      !_archived && const {'owner', 'manager', 'worker'}.contains(_currentRole);

  bool get _canManage =>
      !_archived && const {'owner', 'manager'}.contains(_currentRole);

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _realtimeSubscription = widget.deps.realtimeService.events
        .where((event) => event.projectId == _currentProject.id)
        .listen((_) => _scheduleRealtimeReload());
    _load();
  }

  @override
  void dispose() {
    _realtimeReloadDebounce?.cancel();
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _scheduleRealtimeReload() {
    _realtimeReloadDebounce?.cancel();
    _realtimeReloadDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final generation = ++_loadGeneration;

    final latestProject = <RemoteProject>[];
    final costs = List<RemoteCostItem>.of(_costs);
    final files = List<RemoteProjectFile>.of(_files);
    final members = List<RemoteProjectMember>.of(_members);
    final errors = <String>[];
    final projectId = _currentProject.id;

    await Future.wait<void>([
      _loadSection(
        label: 'Объект',
        load: () => widget.deps.projectRepository.getProject(projectId),
        assign: (value) {
          latestProject
            ..clear()
            ..add(value);
        },
        errors: errors,
      ),
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
    ]);
    if (!mounted) return;
    if (generation != _loadGeneration) return;
    setState(() {
      if (latestProject.isNotEmpty) _project = latestProject.single;
      _costs = costs;
      _files = files;
      _members = members;
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
              PopupMenuItem<String>(value: 'refresh', child: Text('Обновить')),
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
                        project: _currentProject,
                        costs: _costs,
                        members: _members,
                        openTab: (index) => setState(() => _tab = index),
                        onOpenTeam: _openTeam,
                        onAddMember: _canManage
                            ? () => _openTeam(openInvite: true)
                            : null,
                      ),
                      _ExpensesTab(
                        project: _currentProject,
                        repository: widget.deps.costItemRepository,
                        fileRepository: widget.deps.fileRepository,
                        onOpenFile: _openFile,
                        speechToText: widget.deps.speechToText,
                        initial: _costs,
                        onChanged: (items) => setState(() => _costs = items),
                        canContribute: _canContribute,
                        canManage: _canManage,
                      ),
                      _ReportsTab(project: _currentProject, costs: _costs),
                      _MoreTab(
                        project: _currentProject,
                        members: _members,
                        onOpenTeam: _openTeam,
                        onOpenSubscription: _openSubscription,
                        onOpenSupport: _openSupport,
                        onOpenReport: () => setState(() => _tab = 2),
                        onAddMember: _canManage
                            ? () => _openTeam(openInvite: true)
                            : null,
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

  Future<void> _openTeam({bool openInvite = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectTeamScreen(
          projectId: _currentProject.id,
          repository: widget.deps.teamRepository,
          canManage: _canManage,
          openInviteOnLoad: openInvite,
          realtime: widget.deps.realtimeService,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openSupport() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SupportScreen(apiClient: widget.deps.apiClient),
      ),
    );
  }

  Future<void> _openSubscription() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _SubscriptionScreen(
          project: _currentProject,
          members: _members,
          canManage: _canManage,
          apiClient: widget.deps.apiClient,
        ),
      ),
    );
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

  String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return cleaned.isEmpty ? 'online_prorab_file' : cleaned;
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
