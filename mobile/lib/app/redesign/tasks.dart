part of '../online_prorab_redesign.dart';

class _TasksTab extends StatefulWidget {
  const _TasksTab({
    required this.project,
    required this.repository,
    required this.initial,
    required this.onChanged,
  });

  final RemoteProject project;
  final TaskRepository repository;
  final List<RemoteTask> initial;
  final ValueChanged<List<RemoteTask>> onChanged;

  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab> {
  late List<RemoteTask> _tasks;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _tasks = List.of(widget.initial);
  }

  @override
  void didUpdateWidget(covariant _TasksTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) _tasks = List.of(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _tasks.where((task) {
      final done = task.status.toLowerCase() == 'done';
      return _filter == 'all' ||
          (_filter == 'active' && !done) ||
          (_filter == 'done' && done);
    }).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
              const Text(
                'Задачи',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(widget.project.name, style: const TextStyle(color: _muted)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _FilterChip(
                    label: 'Все',
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Активные',
                    selected: _filter == 'active',
                    onTap: () => setState(() => _filter = 'active'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Завершённые',
                    selected: _filter == 'done',
                    onTap: () => setState(() => _filter = 'done'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                const _EmptyCard(
                  icon: Icons.task_alt_rounded,
                  title: 'Задач нет',
                  message: 'Добавьте новую задачу.',
                )
              else
                ...visible.map((task) {
                  final done = task.status.toLowerCase() == 'done';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        leading: IconButton(
                          onPressed: done ? null : () => _markDone(task),
                          icon: Icon(
                            done
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            color: done ? _brand : _muted,
                          ),
                        ),
                        title: Text(
                          task.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: task.description.isEmpty
                            ? null
                            : Text(
                                task.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: FilledButton.icon(
            onPressed: _addTask,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить задачу'),
          ),
        ),
      ],
    );
  }

  Future<void> _markDone(RemoteTask task) async {
    try {
      final updated = await widget.repository.markDone(task);
      final index = _tasks.indexWhere((e) => e.id == task.id);
      if (index < 0 || !mounted) return;
      setState(() => _tasks[index] = updated);
      widget.onChanged(_tasks);
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    }
  }

  Future<void> _addTask() async {
    final result = await showModalBottomSheet<RemoteTask>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateTaskSheet(
        project: widget.project,
        repository: widget.repository,
      ),
    );
    if (result == null) return;
    setState(() => _tasks = [result, ..._tasks]);
    widget.onChanged(_tasks);
  }
}
