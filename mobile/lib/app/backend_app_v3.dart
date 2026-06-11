import 'package:flutter/material.dart';
import 'package:online_prorab/app/backend_project_dashboard_v3.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
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
      title: 'Online Prorab',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: _AuthGate(
        authRepository: _authRepository,
        projectRepository: _projectRepository,
        costItemRepository: _costItemRepository,
        dailyReportRepository: _dailyReportRepository,
        taskRepository: _taskRepository,
        fileRepository: _fileRepository,
        fileDownloadService: _fileDownloadService,
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
    required this.fileDownloadService,
  });

  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  final ProjectFileDownloadService fileDownloadService;
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.authRepository,
    required this.projectRepository,
    required this.costItemRepository,
    required this.dailyReportRepository,
    required this.taskRepository,
    required this.fileRepository,
    required this.fileDownloadService,
  });

  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  final ProjectFileDownloadService fileDownloadService;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<SessionData?> _sessionFuture;

  _AppDependencies get _dependencies => _AppDependencies(
        authRepository: widget.authRepository,
        projectRepository: widget.projectRepository,
        costItemRepository: widget.costItemRepository,
        dailyReportRepository: widget.dailyReportRepository,
        taskRepository: widget.taskRepository,
        fileRepository: widget.fileRepository,
        fileDownloadService: widget.fileDownloadService,
      );

  @override
  void initState() {
    super.initState();
    _sessionFuture = widget.authRepository.loadSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionData?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = snapshot.data;
        if (session != null) {
          return _ProjectsScreen(
            session: session,
            dependencies: _dependencies,
          );
        }
        return _LoginScreen(dependencies: _dependencies);
      },
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
      appBar: AppBar(title: const Text('Online Prorab')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Construction control from your phone',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sign in to sync projects, reports, tasks and files.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phoneController,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Phone number',
              ),
            ),
            if (_codeRequested) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'SMS code',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _codeRequested ? 'Verify and continue' : 'Request code',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Enter a valid phone number');
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
        _showMessage(context, 'SMS code requested');
        return;
      }

      final code = _codeController.text.trim();
      if (code.length != 6) {
        setState(() => _error = 'Enter 6-digit SMS code');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            tooltip: 'Account',
            onPressed: () => _showMessage(
              context,
              'Signed in as ${widget.session.phone}',
            ),
            icon: const Icon(Icons.account_circle),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
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
              message: _friendlyError(snapshot.error),
              onRetry: _refresh,
            );
          }
          final projects = snapshot.data ?? const <RemoteProject>[];
          if (projects.isEmpty) {
            return const _EmptyState(
              icon: Icons.home_work_outlined,
              title: 'No projects yet',
              message: 'Create your first project to start tracking work.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final project = projects[index];
                return Card(
                  child: ListTile(
                    title: Text(
                      project.name.isEmpty ? 'Untitled project' : project.name,
                    ),
                    subtitle: Text(
                      project.address.isEmpty
                          ? project.status
                          : '${project.address} • ${project.status}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openProject(project),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        icon: const Icon(Icons.add),
        label: const Text('Project'),
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
    await widget.dependencies.authRepository.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _LoginScreen(dependencies: widget.dependencies),
      ),
      (_) => false,
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
      appBar: AppBar(title: const Text('Create project')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            enabled: !_busy,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Project name',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            enabled: !_busy,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Address',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create project'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Project name is required');
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
              'Could not load data',
              style: Theme.of(context).textTheme.titleLarge,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

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
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
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
