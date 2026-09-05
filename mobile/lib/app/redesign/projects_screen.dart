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
  String _filter = 'all';
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
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  const _BrandWordmark(),
                  const Spacer(),
                  IconButton(onPressed: () => _toast(context, 'Новых уведомлений нет'), icon: const Icon(Icons.notifications_none_rounded)),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<RemoteProject>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: _brand));
                  }
                  if (snapshot.hasError) {
                    return _ErrorView(message: _errorText(snapshot.error), retry: _reload);
                  }
                  final all = snapshot.data ?? const <RemoteProject>[];
                  final projects = all.where((project) {
                    final query = _search.text.trim().toLowerCase();
                    final matchesQuery = query.isEmpty ||
                        project.name.toLowerCase().contains(query) ||
                        project.address.toLowerCase().contains(query);
                    final status = project.status.toLowerCase();
                    final matchesFilter = _filter == 'all' || status == _filter;
                    return matchesQuery && matchesFilter;
                  }).toList();
                  return RefreshIndicator(
                    onRefresh: _reload,
                    color: _brand,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Объекты', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _ink)),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14)),
                              onPressed: _createProject,
                              icon: const Icon(Icons.add_rounded, size: 20),
                              label: const Text('Добавить'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Поиск по объектам...',
                            prefixIcon: Icon(Icons.search_rounded),
                            suffixIcon: Icon(Icons.tune_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(label: 'Все ${all.length}', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                              const SizedBox(width: 8),
                              _FilterChip(label: 'В работе', selected: _filter == 'active', onTap: () => setState(() => _filter = 'active')),
                              const SizedBox(width: 8),
                              _FilterChip(label: 'Планирование', selected: _filter == 'planning', onTap: () => setState(() => _filter = 'planning')),
                              const SizedBox(width: 8),
                              _FilterChip(label: 'Пауза', selected: _filter == 'paused', onTap: () => setState(() => _filter = 'paused')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (projects.isEmpty)
                          _EmptyCard(
                            icon: Icons.home_work_outlined,
                            title: all.isEmpty ? 'Пока нет объектов' : 'Ничего не найдено',
                            message: all.isEmpty ? 'Добавьте первый строительный объект.' : 'Измените поиск или фильтр.',
                          )
                        else
                          ...projects.map(
                            (project) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ProjectCard(
                                project: project,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => _ProjectWorkspace(project: project, deps: widget.deps)),
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
          if (index == 1) _toast(context, 'Новых уведомлений нет');
          if (index == 2) _showProfile();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_work_outlined), selectedIcon: Icon(Icons.home_work_rounded), label: 'Объекты'),
          NavigationDestination(icon: Icon(Icons.notifications_none_rounded), selectedIcon: Icon(Icons.notifications_rounded), label: 'Уведомления'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Профиль'),
        ],
      ),
    );
  }

  Future<void> _createProject() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ProjectForm(repository: widget.deps.projectRepository)),
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
              const Text('Профиль', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              _InfoRow(icon: Icons.phone_outlined, title: widget.session.phone, subtitle: 'Текущий аккаунт'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: Colors.redAccent),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.deps.authRepository.signOut();
                  if (!mounted) return;
                  Navigator.of(this.context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => _LoginScreen(deps: widget.deps)),
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
