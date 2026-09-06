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
  bool _showArchived = false;
  late Future<List<RemoteProject>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.deps.projectRepository.listProjects(
      includeArchived: _showArchived,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final future = widget.deps.projectRepository.listProjects(
      includeArchived: _showArchived,
    );
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // FutureBuilder displays the error state; refresh callbacks should not
      // surface a second unhandled exception.
    }
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
                  final hasArchived = all.any(
                    (project) => project.status.toLowerCase() == 'archived',
                  );
                  final sourceEmpty = _showArchived
                      ? !hasArchived
                      : all.isEmpty;
                  final projects = all.where((project) {
                    final archived = project.status.toLowerCase() == 'archived';
                    final matchesArchive = _showArchived ? archived : !archived;
                    return matchesArchive &&
                        (query.isEmpty ||
                            project.name.toLowerCase().contains(query) ||
                            project.address.toLowerCase().contains(query));
                  }).toList();
                  return RefreshIndicator(
                    onRefresh: _reload,
                    color: _brand,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                      children: [
                        _PageHeader(
                          title: _showArchived ? 'Архив объектов' : 'Объекты',
                          action: !_showArchived
                              ? IconButton.filled(
                                  style: IconButton.styleFrom(
                                    backgroundColor: _brand,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(44, 44),
                                  ),
                                  tooltip: 'Добавить объект',
                                  onPressed: _createProject,
                                  icon: const Icon(Icons.add_rounded, size: 23),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Поиск объектов',
                            prefixIcon: const Icon(Icons.search_rounded),
                            fillColor: const Color(0xFFEDF1EE),
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(11),
                              ),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(11),
                              ),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(11),
                              ),
                              borderSide: BorderSide(
                                color: _brand,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            selected: _showArchived,
                            label: const Text('Архивные объекты'),
                            avatar: const Icon(Icons.archive_outlined),
                            showCheckmark: false,
                            backgroundColor: Colors.transparent,
                            selectedColor: _brandSoft,
                            side: const BorderSide(color: _line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            visualDensity: VisualDensity.compact,
                            onSelected: _toggleArchived,
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (projects.isEmpty)
                          _EmptyCard(
                            icon: Icons.home_work_outlined,
                            title: sourceEmpty
                                ? (_showArchived
                                      ? 'Архив пуст'
                                      : 'Пока нет объектов')
                                : 'Ничего не найдено',
                            message: sourceEmpty
                                ? (_showArchived
                                      ? 'Здесь появятся объекты, которые вы архивировали.'
                                      : 'Нажмите «+», чтобы создать первый объект.')
                                : 'Попробуйте изменить поисковый запрос.',
                          )
                        else
                          ...List.generate(projects.length, (index) {
                            final project = projects[index];
                            return _ProjectCard(
                              project: project,
                              apiClient: widget.deps.apiClient,
                              showDivider: index < projects.length - 1,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _ProjectWorkspace(
                                    project: project,
                                    deps: widget.deps,
                                    session: widget.session,
                                  ),
                                ),
                              ),
                              onEdit: () => _editProject(project),
                            );
                          }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            height: 68,
            backgroundColor: Colors.white,
            indicatorColor: _ink,
            selectedIconTheme: const IconThemeData(color: Colors.white),
            unselectedIconTheme: const IconThemeData(color: _muted),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected) ? _ink : _muted,
                fontSize: 12,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
        child: NavigationBar(
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
      ),
    );
  }

  Future<void> _createProject() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ProjectForm(
          repository: widget.deps.projectRepository,
          fileRepository: widget.deps.fileRepository,
        ),
      ),
    );
    if (created == true) await _reload();
  }

  Future<void> _toggleArchived(bool value) async {
    setState(() => _showArchived = value);
    await _reload();
  }

  Future<void> _editProject(RemoteProject project) async {
    final updated = await Navigator.of(context).push<RemoteProject>(
      MaterialPageRoute(
        builder: (_) => _ProjectForm(
          repository: widget.deps.projectRepository,
          fileRepository: widget.deps.fileRepository,
          initial: project,
        ),
      ),
    );
    if (updated != null) await _reload();
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
