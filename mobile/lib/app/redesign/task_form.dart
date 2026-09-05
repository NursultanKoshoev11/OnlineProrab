part of '../online_prorab_redesign.dart';

class _CreateTaskSheet extends StatefulWidget {
  const _CreateTaskSheet({required this.project, required this.repository});
  final RemoteProject project;
  final TaskRepository repository;

  @override
  State<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends State<_CreateTaskSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Новая задача',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Название задачи'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Добавить задачу'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      _toast(context, 'Введите название задачи');
      return;
    }
    setState(() => _busy = true);
    try {
      final task = await widget.repository.create(
        projectId: widget.project.id,
        title: _title.text.trim(),
        description: _description.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(task);
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
