import 'package:flutter/material.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/session_store.dart';

class BackendOnlineProrabAppV2 extends StatefulWidget {
  const BackendOnlineProrabAppV2({super.key});

  @override
  State<BackendOnlineProrabAppV2> createState() => _BackendOnlineProrabAppV2State();
}

class _BackendOnlineProrabAppV2State extends State<BackendOnlineProrabAppV2> {
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Online Prorab',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey)),
      home: BackendAuthGateV2(authRepository: authRepository, projectRepository: projectRepository),
    );
  }
}

class BackendAuthGateV2 extends StatefulWidget {
  const BackendAuthGateV2({required this.authRepository, required this.projectRepository, super.key});

  final AuthRepository authRepository;
  final ProjectRepository projectRepository;

  @override
  State<BackendAuthGateV2> createState() => _BackendAuthGateV2State();
}

class _BackendAuthGateV2State extends State<BackendAuthGateV2> {
  late final Future<SessionData?> sessionFuture;

  @override
  void initState() {
    super.initState();
    sessionFuture = widget.authRepository.loadSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionData?>(
      future: sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final session = snapshot.data;
        if (session != null) return BackendProjectsScreenV2(session: session, authRepository: widget.authRepository, projectRepository: widget.projectRepository);
        return BackendLoginScreenV2(authRepository: widget.authRepository, projectRepository: widget.projectRepository);
      },
    );
  }
}

class BackendLoginScreenV2 extends StatefulWidget {
  const BackendLoginScreenV2({required this.authRepository, required this.projectRepository, super.key});

  final AuthRepository authRepository;
  final ProjectRepository projectRepository;

  @override
  State<BackendLoginScreenV2> createState() => _BackendLoginScreenV2State();
}

class _BackendLoginScreenV2State extends State<BackendLoginScreenV2> {
  final phoneController = TextEditingController(text: '+996');
  final codeController = TextEditingController();
  bool codeRequested = false;
  bool busy = false;
  String? error;

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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Construction control from your phone', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('Sign in to sync projects with the backend.'),
          const SizedBox(height: 24),
          TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Phone number')),
          const SizedBox(height: 12),
          if (codeRequested) TextField(controller: codeController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'SMS code')),
          if (codeRequested) const SizedBox(height: 12),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (error != null) const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : _submit, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(codeRequested ? 'Verify and continue' : 'Request code')),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final phone = phoneController.text.trim();
    if (phone.length < 9) {
      setState(() => error = 'Enter a valid phone number');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!codeRequested) {
        await widget.authRepository.requestCode(phone);
        setState(() => codeRequested = true);
        _showMessage(context, 'SMS code requested');
        return;
      }
      final code = codeController.text.trim();
      if (code.length != 6) {
        setState(() => error = 'Enter 6-digit SMS code');
        return;
      }
      final session = await widget.authRepository.verifyCode(phone, code);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BackendProjectsScreenV2(session: session, authRepository: widget.authRepository, projectRepository: widget.projectRepository)));
    } catch (e) {
      setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class BackendProjectsScreenV2 extends StatefulWidget {
  const BackendProjectsScreenV2({required this.session, required this.authRepository, required this.projectRepository, super.key});

  final SessionData session;
  final AuthRepository authRepository;
  final ProjectRepository projectRepository;

  @override
  State<BackendProjectsScreenV2> createState() => _BackendProjectsScreenV2State();
}

class _BackendProjectsScreenV2State extends State<BackendProjectsScreenV2> {
  late Future<List<RemoteProject>> projectsFuture;

  @override
  void initState() {
    super.initState();
    projectsFuture = widget.projectRepository.listProjects();
  }

  Future<void> _refresh() async {
    setState(() => projectsFuture = widget.projectRepository.listProjects());
    await projectsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: FutureBuilder<List<RemoteProject>>(
        future: projectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return ErrorStateV2(message: _friendlyError(snapshot.error), onRetry: _refresh);
          final projects = snapshot.data ?? const <RemoteProject>[];
          if (projects.isEmpty) return const EmptyStateV2(icon: Icons.home_work_outlined, title: 'No projects yet', message: 'Create your first project to start tracking work.');
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final project = projects[index];
                return Card(child: ListTile(title: Text(project.name.isEmpty ? 'Untitled project' : project.name), subtitle: Text(project.address.isEmpty ? project.status : '${project.address} • ${project.status}'), trailing: const Icon(Icons.chevron_right)));
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createProject, icon: const Icon(Icons.add), label: const Text('Project')),
    );
  }

  Future<void> _createProject() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BackendProjectFormScreenV2(projectRepository: widget.projectRepository)));
    if (created == true) await _refresh();
  }

  Future<void> _signOut() async {
    await widget.authRepository.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => BackendLoginScreenV2(authRepository: widget.authRepository, projectRepository: widget.projectRepository)), (_) => false);
  }
}

class BackendProjectFormScreenV2 extends StatefulWidget {
  const BackendProjectFormScreenV2({required this.projectRepository, super.key});

  final ProjectRepository projectRepository;

  @override
  State<BackendProjectFormScreenV2> createState() => _BackendProjectFormScreenV2State();
}

class _BackendProjectFormScreenV2State extends State<BackendProjectFormScreenV2> {
  final nameController = TextEditingController();
  final addressController = TextEditingController();
  bool busy = false;
  String? error;

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
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (error != null) const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : _save, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create project')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Project name is required');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.projectRepository.createProject(name: name, address: addressController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class ErrorStateV2 extends StatelessWidget {
  const ErrorStateV2({required this.message, required this.onRetry, super.key});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 56), const SizedBox(height: 16), Text('Could not load data', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center), const SizedBox(height: 16), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry'))])));
  }
}

class EmptyStateV2 extends StatelessWidget {
  const EmptyStateV2({required this.icon, required this.title, required this.message, super.key});
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
