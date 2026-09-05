part of '../online_prorab_redesign.dart';

class _ProjectsScreen extends StatefulWidget {
  const _ProjectsScreen({required this.session, required this.deps});

  final SessionData session;
  final _Dependencies deps;

  @override
  State<_ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<_ProjectsScreen> {
  final _search = TextEditingController();
  late Future<List<RemoteProject>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.deps.projectRepository.listProjects();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final future = widget.deps.projectRepository.listProjects();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  const _BrandWordmark(),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Профиль',
                    onPressed: _showProfile,
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<RemoteProject>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: _brand),
                    );
                  }
                  if (snapshot.hasError) {
                    return _ErrorView(
                      message: _errorText(snapshot.error),
                      retry: _reload,
                    );
                  }
                  final all = snapshot.data ?? const <RemoteProject>[];
                  final query = _search.text.trim().toLowerCase();
                  final projects = all.where((project) {
                    return query.isEmpty ||
                        project.name.toLowerCase().contains(query) ||
                        project.address.toLowerCase().contains(query);
                  }).toList();
                  return RefreshIndicator(
                    onRefresh: _reload,
                    color: _brand,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Объекты',
                                style: TextStyle(
                                  fontSize: 31,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                  color: _ink,
                                ),
                              ),
                            ),
                            IconButton.filled(
                              style: IconButton.styleFrom(
                                backgroundColor: _brand,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(46, 46),
                              ),
                              tooltip: 'Добавить объект',
                              onPressed: _createProject,
                              icon: const Icon(Icons.add_rounded, size: 25),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Поиск объектов',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (projects.isEmpty)
                          _EmptyCard(
                            icon: Icons.home_work_outlined,
                            title: all.isEmpty
                                ? 'Пока нет объектов'
                                : 'Ничего не найдено',
                            message: all.isEmpty
                                ? 'Нажмите «+», чтобы создать первый объект.'
                                : 'Попробуйте изменить поисковый запрос.',
                          )
                        else
                          ...projects.map(
                            (project) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ProjectCard(
                                project: project,
                                apiClient: widget.deps.apiClient,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => _ProjectWorkspace(
                                      project: project,
                                      deps: widget.deps,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) _showProfile();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_work_outlined),
            selectedIcon: Icon(Icons.home_work_rounded),
            label: 'Объекты',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }

  Future<void> _createProject() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ProjectForm(repository: widget.deps.projectRepository),
      ),
    );
    if (created == true) await _reload();
  }

  Future<void> _showProfile() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Профиль',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.phone_outlined,
                title: widget.session.phone,
                subtitle: 'Текущий аккаунт',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.deps.authRepository.signOut();
                  if (!mounted) return;
                  Navigator.of(this.context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => _LoginScreen(deps: widget.deps),
                    ),
                    (_) => false,
                  );
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Выйти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
