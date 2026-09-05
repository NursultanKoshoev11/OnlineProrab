part of '../online_prorab_redesign.dart';

class _CostDetails extends StatelessWidget {
  const _CostDetails({required this.item});
  final RemoteCostItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Расход',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _brandSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      size: 28,
                      color: _brand,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _money(item.amount, item.currency),
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: _brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (item.spentAt.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _DetailRow(
                  label: 'Дата',
                  value: _displayIsoDate(item.spentAt),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProjectForm extends StatefulWidget {
  const _ProjectForm({required this.repository});

  final ProjectRepository repository;

  @override
  State<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<_ProjectForm> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  DateTime _startDate = DateTime.now();
  String? _coverPath;
  String? _coverName;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Новый объект',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          _ProjectCoverPicker(
            path: _coverPath,
            busy: _busy,
            onPick: _pickCover,
            onRemove: () => setState(() {
              _coverPath = null;
              _coverName = null;
            }),
          ),
          const SizedBox(height: 22),
          const Text(
            'Название объекта',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Например: Дом в Кок-Жаре',
              prefixIcon: Icon(Icons.home_work_outlined),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Адрес',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _address,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Например: с. Кок-Жар, ул. Центральная, 10',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Дата начала',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: _busy ? null : _pickStartDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(
                _displayDate(_startDate),
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Нужна, чтобы показывать срок строительства объекта.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: _line)),
          ),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Создать объект'),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCover() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result == null || result.isEmpty) return;
      final selected = result.single;
      final path = selected.path;
      if (path == null || path.trim().isEmpty) {
        setState(() => _error = 'Не удалось получить выбранное фото');
        return;
      }
      setState(() {
        _coverPath = path;
        _coverName = selected.name;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось выбрать фото');
    }
  }

  Future<void> _pickStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) setState(() => _startDate = selected);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название объекта');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final coverPath = _coverPath;
      if (coverPath == null) {
        await widget.repository.createProject(
          name: name,
          address: _address.text.trim(),
          startDate: _apiDate(_startDate),
        );
      } else {
        await widget.repository.createProjectWithCover(
          name: name,
          address: _address.text.trim(),
          startDate: _apiDate(_startDate),
          filePath: coverPath,
          fileName: _coverName ?? 'project-cover.jpg',
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ProjectCoverPicker extends StatelessWidget {
  const _ProjectCoverPicker({
    required this.path,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final String? path;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final selectedPath = path;
    if (selectedPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 205,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(selectedPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _CoverPlaceholder(),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xB3000000),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : onPick,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Заменить'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: busy ? null : onPick,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _line, width: 1.4),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundIcon(icon: Icons.add_a_photo_outlined, size: 58),
            SizedBox(height: 12),
            Text(
              'Добавить фото объекта',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 5),
            Text(
              'Будет обложкой в списке объектов',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
