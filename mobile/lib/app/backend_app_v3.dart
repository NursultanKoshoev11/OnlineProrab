import 'package:flutter/material.dart';
import 'package:online_prorab/app/backend_project_dashboard_v3.dart';
import 'package:online_prorab/app/online_prorab_theme.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/features/projects/project_team_repository.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/project_file_download_service.dart';
import 'package:online_prorab/services/session_store.dart';

class BackendOnlineProrabAppV3 extends StatefulWidget {
  const BackendOnlineProrabAppV3({super.key});

  @override
  State<BackendOnlineProrabAppV3> createState() =>
      _BackendOnlineProrabAppV3State();
}

class _BackendOnlineProrabAppV3State extends State<BackendOnlineProrabAppV3> {
  late final ApiClient _apiClient;
  late final AuthRepository _authRepository;
  late final ProjectRepository _projectRepository;
  late final CostItemRepository _costItemRepository;
  late final DailyReportRepository _dailyReportRepository;
  late final TaskRepository _taskRepository;
  late final ProjectFileRepository _fileRepository;
  late final ProjectTeamRepository _teamRepository;
  late final ProjectFileDownloadService _fileDownloadService;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _authRepository = AuthRepository(
      apiClient: _apiClient,
      sessionStore: SessionStore(),
    );
    _projectRepository = ProjectRepository(apiClient: _apiClient);
    _costItemRepository = CostItemRepository(apiClient: _apiClient);
    _dailyReportRepository = DailyReportRepository(apiClient: _apiClient);
    _taskRepository = TaskRepository(apiClient: _apiClient);
    _fileRepository = ProjectFileRepository(apiClient: _apiClient);
    _teamRepository = ProjectTeamRepository(apiClient: _apiClient);
    _fileDownloadService = ProjectFileDownloadService(apiClient: _apiClient);
  }

  @override
  void dispose() {
    _fileDownloadService.close();
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OnlinePRorab',
      theme: buildOnlineProrabTheme(),
      home: _AuthGate(
        dependencies: _AppDependencies(
          authRepository: _authRepository,
          projectRepository: _projectRepository,
          costItemRepository: _costItemRepository,
          dailyReportRepository: _dailyReportRepository,
          taskRepository: _taskRepository,
          fileRepository: _fileRepository,
          teamRepository: _teamRepository,
          fileDownloadService: _fileDownloadService,
        ),
      ),
    );
  }
}

class _AppDependencies {
  const _AppDependencies({
    required this.authRepository,
    required this.projectRepository,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    required this.fileRepository,
    required this.teamRepository,
    required this.fileDownloadService,
  });

  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  final ProjectTeamRepository teamRepository;
  final ProjectFileDownloadService fileDownloadService;
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.dependencies});

  final _AppDependencies dependencies;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<SessionData?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = widget.dependencies.authRepository.loadSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionData?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }
        if (snapshot.data != null) {
          return _ProjectsScreen(
            session: snapshot.data!,
            dependencies: widget.dependencies,
          );
        }
        return _LoginScreen(dependencies: widget.dependencies);
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(size: 64),
            SizedBox(height: 18),
            Text(
              'OnlinePRorab',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: OnlineProrabColors.text,
              ),
            ),
            SizedBox(height: 22),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.dependencies});

  final _AppDependencies dependencies;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _phoneController = TextEditingController(text: '+996');
  final _codeController = TextEditingController();
  bool _codeRequested = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _BrandMark(size: 58),
                ),
                const SizedBox(height: 30),
                Text('Стройка под контролем',
                    style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 10),
                const Text(
                  'Объекты, расходы, задачи, отчёты и команда — в одном приложении.',
                  style: TextStyle(
                    color: OnlineProrabColors.textMuted,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _phoneController,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Номер телефона',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                if (_codeRequested) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _codeController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Код из SMS',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _InlineError(message: _error!),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_codeRequested ? 'Войти' : 'Получить код'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Введите корректный номер телефона.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (!_codeRequested) {
        await widget.dependencies.authRepository.requestCode(phone);
        if (!mounted) return;
        setState(() => _codeRequested = true);
        _showMessage(context, 'Код отправлен.');
        return;
      }

      final code = _codeController.text.trim();
      if (code.length != 6) {
        setState(() => _error = 'Введите шестизначный код из SMS.');
        return;
      }

      final session =
          await widget.dependencies.authRepository.verifyCode(phone, code);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => _ProjectsScreen(
            session: session,
            dependencies: widget.dependencies,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ProjectsScreen extends StatefulWidget {
  const _ProjectsScreen({
    required this.session,
    required this.dependencies,
  });

  final SessionData session;
  final _AppDependencies dependencies;

  @override
  State<_ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<_ProjectsScreen> {
  late Future<List<RemoteProject>> _projectsFuture;
  String _query = '';
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _projectsFuture = widget.dependencies.projectRepository.listProjects();
  }

  Future<void> _refresh() async {
    final future = widget.dependencies.projectRepository.listProjects();
    setState(() => _projectsFuture = future);
    await future;
  }

  List<RemoteProject> _filtered(List<RemoteProject> projects) {
    final query = _query.trim().toLowerCase();
    return projects.where((project) {
      final matchesQuery = query.isEmpty ||
          project.name.toLowerCase().contains(query) ||
          project.address.toLowerCase().contains(query);
      final normalized = project.status.toLowerCase();
      final matchesStatus = _status == 'all' ||
          (_status == 'active' &&
              normalized != 'completed' &&
              normalized != 'done') ||
          (_status == 'completed' &&
              (normalized == 'completed' || normalized == 'done'));
      return matchesQuery && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(size: 34),
            SizedBox(width: 10),
            Text(
              'OnlinePRorab',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Профиль',
            icon: const CircleAvatar(
              radius: 17,
              backgroundColor: OnlineProrabColors.mint,
              child: Icon(
                Icons.person_outline_rounded,
                color: OnlineProrabColors.primary,
                size: 20,
              ),
            ),
            onSelected: (value) {
              if (value == 'phone') {
                _showMessage(context, widget.session.phone);
              }
              if (value == 'logout') _signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'phone',
                child: Text(widget.session.phone),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('Выйти'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<RemoteProject>>(
        future: _projectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              title: 'Не удалось загрузить объекты',
              message: _friendlyError(snapshot.error),
              onRetry: _refresh,
            );
          }

          final allProjects = snapshot.data ?? const <RemoteProject>[];
          final projects = _filtered(allProjects);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
              children: [
                Text('Мои объекты',
                    style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 7),
                Text(
                  '${allProjects.length} ${_objectWord(allProjects.length)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Найти объект по названию или адресу',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'Все',
                        selected: _status == 'all',
                        onTap: () => setState(() => _status = 'all'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'В работе',
                        selected: _status == 'active',
                        onTap: () => setState(() => _status = 'active'),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Завершённые',
                        selected: _status == 'completed',
                        onTap: () => setState(() => _status = 'completed'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (projects.isEmpty)
                  _EmptyProjects(
                    hasAnyProjects: allProjects.isNotEmpty,
                    onCreate: _createProject,
                  )
                else
                  ...projects.map(
                    (project) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ProjectCard(
                        project: project,
                        onTap: () => _openProject(project),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 0,
        backgroundColor: OnlineProrabColors.primary,
        foregroundColor: Colors.white,
        onPressed: _createProject,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Добавить объект',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  void _openProject(RemoteProject project) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BackendProjectDashboardScreenV3(
          project: project,
          costItemRepository: widget.dependencies.costItemRepository,
          dailyReportRepository: widget.dependencies.dailyReportRepository,
          taskRepository: widget.dependencies.taskRepository,
          fileRepository: widget.dependencies.fileRepository,
          teamRepository: widget.dependencies.teamRepository,
          fileDownloadService: widget.dependencies.fileDownloadService,
        ),
      ),
    );
  }

  Future<void> _createProject() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ProjectFormScreen(
          repository: widget.dependencies.projectRepository,
        ),
      ),
    );
    if (created == true) await _refresh();
  }

  Future<void> _signOut() async {
    try {
      await widget.dependencies.authRepository.signOut();
    } catch (_) {
      // Local session is still cleared by the repository when possible.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _LoginScreen(dependencies: widget.dependencies),
      ),
      (_) => false,
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final RemoteProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completed = _isCompleted(project.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 124,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFDDE8E2), Color(0xFFBFD0C7)],
                ),
              ),
              child: Stack(
                children: [
                  const Positioned(
                    right: 24,
                    bottom: 12,
                    child: Icon(
                      Icons.apartment_rounded,
                      size: 92,
                      color: Color(0x55315F4D),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: completed
                            ? Colors.white.withValues(alpha: .9)
                            : OnlineProrabColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        completed ? 'Завершён' : 'В работе',
                        style: TextStyle(
                          color: completed
                              ? OnlineProrabColors.primary
                              : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name.isEmpty ? 'Без названия' : project.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (project.address.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 17,
                                color: OnlineProrabColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  project.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 17,
                      color: OnlineProrabColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectFormScreen extends StatefulWidget {
  const _ProjectFormScreen({required this.repository});

  final ProjectRepository repository;

  @override
  State<_ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<_ProjectFormScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый объект')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Text('Добавить объект',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text(
              'Укажите основную информацию. Остальные данные можно добавить внутри объекта.',
              style: TextStyle(color: OnlineProrabColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 26),
            TextField(
              controller: _nameController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Название объекта',
                prefixIcon: Icon(Icons.home_work_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Адрес',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _InlineError(message: _error!),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Создать объект'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название объекта.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createProject(
        name: name,
        address: _addressController.text.trim(),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? Colors.white : OnlineProrabColors.text,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OnlineProrabColors.primary,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(
        Icons.home_work_rounded,
        color: Colors.white,
        size: size * .54,
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECE9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 19),
          const SizedBox(width: 9),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.hasAnyProjects, required this.onCreate});

  final bool hasAnyProjects;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 38),
      decoration: BoxDecoration(
        color: OnlineProrabColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: OnlineProrabColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.home_work_outlined,
            size: 52,
            color: OnlineProrabColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            hasAnyProjects ? 'Ничего не найдено' : 'Объектов пока нет',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          Text(
            hasAnyProjects
                ? 'Измените поиск или фильтр.'
                : 'Создайте первый объект и начните вести стройку.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!hasAnyProjects) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить объект'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
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
            Text(title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
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

bool _isCompleted(String status) {
  final value = status.toLowerCase();
  return value == 'completed' || value == 'done';
}

String _objectWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return 'объект';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'объекта';
  }
  return 'объектов';
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
