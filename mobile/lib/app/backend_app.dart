import 'package:flutter/material.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/session_store.dart';

class BackendOnlineProrabApp extends StatefulWidget {
  const BackendOnlineProrabApp({super.key});

  @override
  State<BackendOnlineProrabApp> createState() => _BackendOnlineProrabAppState();
}

class _BackendOnlineProrabAppState extends State<BackendOnlineProrabApp> {
  late final ApiClient apiClient;
  late final AuthRepository authRepository;
  late final ProjectRepository projectRepository;

  @override
  void initState() {
    super.initState();
    apiClient = ApiClient();
    authRepository = AuthRepository(apiClient: apiClient, sessionStore: SessionStore());
    projectRepository = ProjectRepository(apiClient: apiClient);
  }

  @override
  void dispose() {
    apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackendServices(
      authRepository: authRepository,
      projectRepository: projectRepository,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Online Prorab',
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey)),
        home: const BackendAuthGate(),
      ),
    );
  }
}

class BackendServices extends InheritedWidget {
  const BackendServices({required this.authRepository, required this.projectRepository, required super.child, super.key});

  final AuthRepository authRepository;
  final ProjectRepository projectRepository;

  static BackendServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<BackendServices>();
    assert(services != null, 'BackendServices not found');
    return services!;
  }

  @override
  bool updateShouldNotify(BackendServices oldWidget) {
    return authRepository != oldWidget.authRepository || projectRepository != oldWidget.projectRepository;
  }
}

class BackendAuthGate extends StatefulWidget {
  const BackendAuthGate({super.key});

  @override
  State<BackendAuthGate> createState() => _BackendAuthGateState();
}

class _BackendAuthGateState extends State<BackendAuthGate> {
  late Future<SessionData?> sessionFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sessionFuture = BackendServices.of(context).authRepository.loadSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionData?>(
      future: sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data != null) {
          return BackendProjectsScreen(session: snapshot.data!);
        }
        return BackendLoginScreen(onSignedIn: _openProjects);
      },
    );
  }

  void _openProjects(SessionData session) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BackendProjectsScreen(session: session)));
  }
}

class BackendLoginScreen extends StatefulWidget {
  const BackendLoginScreen({required this.onSignedIn, super.key});

  final ValueChanged<SessionData> onSignedIn;

  @override
  State<BackendLoginScreen> createState() => _BackendLoginScreenState();
}

class _BackendLoginScreenState extends State<BackendLoginScreen> {
  final phoneController = TextEditingController(text: '+996');
  final codeController = TextEditingController();
  bool codeRequested = false;
  bool isSubmitting = false;
  String? errorMessage;

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
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Construction control from your phone', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Sign in with your phone number to sync projects with the backend.'),
            const SizedBox(height: 24),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Phone number', hintText: '+996...'),
            ),
            const SizedBox(height: 12),
            if (codeRequested) ...[
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'SMS code'),
              ),
              const SizedBox(height: 12),
            ],
            if (errorMessage != null) ...[
              Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(codeRequested ? 'Verify and continue' : 'Request code'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final phone = phoneController.text.trim();
    final repository = BackendServices.of(context).authRepository;
    if (phone.length < 9) {
      setState(() => errorMessage = 'Enter a valid phone number');
      return;
    }

    setState(() {
      isSubmitting = true;
      errorMessage = null;
    });

    try {
      if (!codeRequested) {
        await repository.requestCode(phone);
        setState(() => codeRequested = true);
        _showMessage(context, 'SMS code requested');
        return;
      }

      final code = codeController.text.trim();
      if (code.length != 6) {
        setState(() => errorMessage = 'Enter 6-digit SMS code');
        return;
      }
      final session = await repository.verifyCode(phone, code);
      widget.onSignedIn(session);
    } catch (error) {
      setState(() => errorMessage = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }
}

class BackendProjectsScreen extends StatefulWidget {
  const BackendProjectsScreen({required this.session, super.key});

  final SessionData session;

  @override
  State<BackendProjectsScreen> createState() => _BackendProjectsScreenState();
}

class _BackendProjectsScreenState extends State<BackendProjectsScreen> {
  late Future<List<RemoteProject>> projectsFuture;

  @override
  void initState() {
    super.initState();
    projectsFuture = _loadProjects();
  }

  Future<List<RemoteProject>> _loadProjects() {
    return BackendServices.of(context).projectRepository.listProjects();
  }

  void _refresh() {
    setState(() => projectsFuture = _loadProjects());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(tooltip: 'Signed in phone', onPressed: () => _showMessage(context, 'Signed in as ${widget.session.phone}'), icon: const Icon(Icons.account_circle)),
          IconButton(tooltip: 'Sign out', onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: FutureBuilder<List<RemoteProject>>(
        future: projectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(message: _friendlyError(snapshot.error), onRetry: _refresh);
          }
          final projects = snapshot.data ?? const <RemoteProject>[];
          if (projects.isEmpty) {
            return const EmptyState(icon: Icons.home_work_outlined, title: 'No projects yet', message: 'Create your first house project to start tracking work.');
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final project = projects[index];
                return Card(
                  child: ListTile(
                    title: Text(project.name.isEmpty ? 'Untitled project' : project.name),
                    subtitle: Text(project.address.isEmpty ? project.status : '${project.address} • ${project.status}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showMessage(context, 'Dashboard sync is the next step for ${project.name}'),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createProject, icon: const Icon(Icons.add), label: const Text('Project')),
    );
  }

  Future<void> _createProject() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const BackendProjectFormScreen()));
    if (created == true) {
      _refresh();
    }
  }

  Future<void> _signOut() async {
    await BackendServices.of(context).authRepository.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => BackendLoginScreen(onSignedIn: (session) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BackendProjectsScreen(session: session))))), (_) => false);
  }
}

class BackendProjectFormScreen extends StatefulWidget {
  const BackendProjectFormScreen({super.key});

  @override
  State<BackendProjectFormScreen> createState() => _BackendProjectFormScreenState();
}

class _BackendProjectFormScreenState extends State<BackendProjectFormScreen> {
  final nameController = TextEditingController();
  final addressController = TextEditingController();
  bool isSaving = false;
  String? errorMessage;

  @override
  void dispose() {
    nameController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create project')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: nameController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Project name')),
          const SizedBox(height: 12),
          TextField(controller: addressController, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Address')),
          const SizedBox(height: 16),
          if (errorMessage != null) ...[
            Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: isSaving ? null : _save,
            child: isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create project'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(() => errorMessage = 'Project name is required');
      return;
    }
    setState(() {
      isSaving = true;
      errorMessage = null;
    });
    try {
      await BackendServices.of(context).projectRepository.createProject(name: name, address: addressController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() => errorMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, required this.onRetry, super.key});

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
            Text('Could not load data', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
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
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 56), const SizedBox(height: 16), Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center)])));
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _friendlyError(Object? error) {
  final text = error.toString();
  if (text.contains('408') || text.contains('timed out')) return 'Server timeout. Check internet or backend status.';
  if (text.contains('401')) return 'Session expired. Please sign in again.';
  if (text.contains('Connection refused') || text.contains('ApiException(0)')) return 'Cannot connect to backend. Check API_BASE_URL and server status.';
  if (text.contains('invalid JSON')) return 'Backend returned an invalid response.';
  return text.replaceFirst('Exception: ', '');
}
