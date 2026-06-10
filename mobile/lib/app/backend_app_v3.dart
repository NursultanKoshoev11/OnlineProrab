import 'package:flutter/material.dart';
import 'package:online_prorab/app/backend_project_dashboard_v2.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/session_store.dart';

class BackendOnlineProrabAppV3 extends StatefulWidget {
  const BackendOnlineProrabAppV3({super.key});

  @override
  State<BackendOnlineProrabAppV3> createState() => _BackendOnlineProrabAppV3State();
}

class _BackendOnlineProrabAppV3State extends State<BackendOnlineProrabAppV3> {
  late final ApiClient apiClient;
  late final AuthRepository authRepository;
  late final ProjectRepository projectRepository;
  late final CostItemRepository costItemRepository;
  late final DailyReportRepository dailyReportRepository;
  late final TaskRepository taskRepository;
  late final ProjectFileRepository fileRepository;

  @override
  void initState() {
    super.initState();
    apiClient = ApiClient();
    authRepository = AuthRepository(apiClient: apiClient, sessionStore: SessionStore());
    projectRepository = ProjectRepository(apiClient: apiClient);
    costItemRepository = CostItemRepository(apiClient: apiClient);
    dailyReportRepository = DailyReportRepository(apiClient: apiClient);
    taskRepository = TaskRepository(apiClient: apiClient);
    fileRepository = ProjectFileRepository(apiClient: apiClient);
  }

  @override
  void dispose() {
    apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Online Prorab',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey)),
      home: BackendAuthGateV3(
        authRepository: authRepository,
        projectRepository: projectRepository,
        costItemRepository: costItemRepository,
        dailyReportRepository: dailyReportRepository,
        taskRepository: taskRepository,
        fileRepository: fileRepository,
      ),
    );
  }
}

class BackendAuthGateV3 extends StatefulWidget {
  const BackendAuthGateV3({required this.authRepository, required this.projectRepository, required this.costItemRepository, required this.dailyReportRepository, required this.taskRepository, required this.fileRepository, super.key});
  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;

  @override
  State<BackendAuthGateV3> createState() => _BackendAuthGateV3State();
}

class _BackendAuthGateV3State extends State<BackendAuthGateV3> {
  late final Future<SessionData?> sessionFuture;
  @override
  void initState() { super.initState(); sessionFuture = widget.authRepository.loadSession(); }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionData?>(future: sessionFuture, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final session = snapshot.data;
      if (session != null) return _projectsScreen(session);
      return BackendLoginScreenV3(onSignedIn: _projectsScreen, authRepository: widget.authRepository);
    });
  }
  Widget _projectsScreen(SessionData session) => BackendProjectsScreenV3(session: session, authRepository: widget.authRepository, projectRepository: widget.projectRepository, costItemRepository: widget.costItemRepository, dailyReportRepository: widget.dailyReportRepository, taskRepository: widget.taskRepository, fileRepository: widget.fileRepository);
}

class BackendLoginScreenV3 extends StatefulWidget {
  const BackendLoginScreenV3({required this.onSignedIn, required this.authRepository, super.key});
  final Widget Function(SessionData session) onSignedIn;
  final AuthRepository authRepository;
  @override
  State<BackendLoginScreenV3> createState() => _BackendLoginScreenV3State();
}

class _BackendLoginScreenV3State extends State<BackendLoginScreenV3> {
  final phoneController = TextEditingController(text: '+996');
  final codeController = TextEditingController();
  bool codeRequested = false;
  bool busy = false;
  String? error;
  @override
  void dispose() { phoneController.dispose(); codeController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Online Prorab')), body: ListView(padding: const EdgeInsets.all(20), children: [const Text('Construction control from your phone', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const Text('Sign in to sync projects, reports, tasks and files with backend.'), const SizedBox(height: 24), TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Phone number')), const SizedBox(height: 12), if (codeRequested) TextField(controller: codeController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'SMS code')), if (codeRequested) const SizedBox(height: 12), if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), if (error != null) const SizedBox(height: 12), FilledButton(onPressed: busy ? null : _submit, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(codeRequested ? 'Verify and continue' : 'Request code'))]));
  Future<void> _submit() async { final phone = phoneController.text.trim(); if (phone.length < 9) { setState(() => error = 'Enter a valid phone number'); return; } setState(() { busy = true; error = null; }); try { if (!codeRequested) { await widget.authRepository.requestCode(phone); setState(() => codeRequested = true); _showMessage(context, 'SMS code requested'); return; } final code = codeController.text.trim(); if (code.length != 6) { setState(() => error = 'Enter 6-digit SMS code'); return; } final session = await widget.authRepository.verifyCode(phone, code); if (!mounted) return; Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.onSignedIn(session))); } catch (e) { setState(() => error = _friendlyError(e)); } finally { if (mounted) setState(() => busy = false); } }
}

class BackendProjectsScreenV3 extends StatefulWidget {
  const BackendProjectsScreenV3({required this.session, required this.authRepository, required this.projectRepository, required this.costItemRepository, required this.dailyReportRepository, required this.taskRepository, required this.fileRepository, super.key});
  final SessionData session;
  final AuthRepository authRepository;
  final ProjectRepository projectRepository;
  final CostItemRepository costItemRepository;
  final DailyReportRepository dailyReportRepository;
  final TaskRepository taskRepository;
  final ProjectFileRepository fileRepository;
  @override
  State<BackendProjectsScreenV3> createState() => _BackendProjectsScreenV3State();
}

class _BackendProjectsScreenV3State extends State<BackendProjectsScreenV3> {
  late Future<List<RemoteProject>> projectsFuture;
  @override
  void initState() { super.initState(); projectsFuture = widget.projectRepository.listProjects(); }
  Future<void> _refresh() async { setState(() => projectsFuture = widget.projectRepository.listProjects()); await projectsFuture; }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Projects'), actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)), IconButton(onPressed: _signOut, icon: const Icon(Icons.logout))]), body: FutureBuilder<List<RemoteProject>>(future: projectsFuture, builder: (context, snapshot) { if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator()); if (snapshot.hasError) return ErrorStateV3(message: _friendlyError(snapshot.error), onRetry: _refresh); final projects = snapshot.data ?? const <RemoteProject>[]; if (projects.isEmpty) return const EmptyStateV3(icon: Icons.home_work_outlined, title: 'No projects yet', message: 'Create your first project to start tracking work.'); return RefreshIndicator(onRefresh: _refresh, child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: projects.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) { final project = projects[index]; return Card(child: ListTile(title: Text(project.name.isEmpty ? 'Untitled project' : project.name), subtitle: Text(project.address.isEmpty ? project.status : '${project.address} • ${project.status}'), trailing: const Icon(Icons.chevron_right), onTap: () => _openProject(project))); })); }), floatingActionButton: FloatingActionButton.extended(onPressed: _createProject, icon: const Icon(Icons.add), label: const Text('Project')));
  void _openProject(RemoteProject project) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BackendProjectDashboardScreenV2(project: project, costItemRepository: widget.costItemRepository, dailyReportRepository: widget.dailyReportRepository, taskRepository: widget.taskRepository, fileRepository: widget.fileRepository)));
  Future<void> _createProject() async { final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BackendProjectFormScreenV3(projectRepository: widget.projectRepository))); if (created == true) await _refresh(); }
  Future<void> _signOut() async { await widget.authRepository.signOut(); if (!mounted) return; Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => BackendLoginScreenV3(onSignedIn: (session) => BackendProjectsScreenV3(session: session, authRepository: widget.authRepository, projectRepository: widget.projectRepository, costItemRepository: widget.costItemRepository, dailyReportRepository: widget.dailyReportRepository, taskRepository: widget.taskRepository, fileRepository: widget.fileRepository), authRepository: widget.authRepository)), (_) => false); }
}

class BackendProjectFormScreenV3 extends StatefulWidget { const BackendProjectFormScreenV3({required this.projectRepository, super.key}); final ProjectRepository projectRepository; @override State<BackendProjectFormScreenV3> createState() => _BackendProjectFormScreenV3State(); }
class _BackendProjectFormScreenV3State extends State<BackendProjectFormScreenV3> { final nameController = TextEditingController(); final addressController = TextEditingController(); bool busy = false; String? error; @override void dispose() { nameController.dispose(); addressController.dispose(); super.dispose(); } @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Create project')), body: ListView(padding: const EdgeInsets.all(16), children: [TextField(controller: nameController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Project name')), const SizedBox(height: 12), TextField(controller: addressController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Address')), const SizedBox(height: 16), if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)), if (error != null) const SizedBox(height: 12), FilledButton(onPressed: busy ? null : _save, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create project'))])); Future<void> _save() async { final name = nameController.text.trim(); if (name.isEmpty) { setState(() => error = 'Project name is required'); return; } setState(() { busy = true; error = null; }); try { await widget.projectRepository.createProject(name: name, address: addressController.text.trim()); if (mounted) Navigator.of(context).pop(true); } catch (e) { setState(() => error = _friendlyError(e)); } finally { if (mounted) setState(() => busy = false); } } }

class ErrorStateV3 extends StatelessWidget { const ErrorStateV3({required this.message, required this.onRetry, super.key}); final String message; final VoidCallback onRetry; @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 56), const SizedBox(height: 16), Text('Could not load data', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry'))]))); }
class EmptyStateV3 extends StatelessWidget { const EmptyStateV3({required this.icon, required this.title, required this.message, super.key}); final IconData icon; final String title; final String message; @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 56), const SizedBox(height: 16), Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center)]))); }
void _showMessage(BuildContext context, String message) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
String _friendlyError(Object? error) { final text = error.toString(); if (text.contains('408') || text.contains('timed out')) return 'Server timeout. Check internet or backend status.'; if (text.contains('401')) return 'Session expired. Please sign in again.'; if (text.contains('Connection refused') || text.contains('ApiException(0)')) return 'Cannot connect to backend. Check API_BASE_URL and server status.'; if (text.contains('invalid JSON')) return 'Backend returned an invalid response.'; return text.replaceFirst('Exception: ', ''); }
