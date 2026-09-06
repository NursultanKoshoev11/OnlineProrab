part of '../online_prorab_redesign.dart';

class _CostDetails extends StatefulWidget {
  const _CostDetails({
    required this.item,
    required this.repository,
    required this.fileRepository,
    required this.onOpenFile,
    required this.canContribute,
    required this.canManage,
  });

  final RemoteCostItem item;
  final CostItemRepository repository;
  final ProjectFileRepository fileRepository;
  final ValueChanged<RemoteProjectFile> onOpenFile;
  final bool canContribute;
  final bool canManage;

  @override
  State<_CostDetails> createState() => _CostDetailsState();
}

class _CostDetailsState extends State<_CostDetails> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Расход',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (widget.canContribute)
            IconButton(
              tooltip: 'Изменить расход',
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (widget.canManage)
            IconButton(
              tooltip: 'Удалить расход',
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
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
                          widget.item.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _money(widget.item.amount, widget.item.currency),
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
          if (widget.item.spentAt.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _DetailRow(
                  label: 'Дата',
                  value: _displayIsoDate(widget.item.spentAt),
                ),
              ),
            ),
          ],
          if (widget.item.category.isNotEmpty ||
              widget.item.vendor.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    if (widget.item.category.isNotEmpty)
                      _DetailRow(
                        label: 'Категория',
                        value: widget.item.category,
                      ),
                    if (widget.item.category.isNotEmpty &&
                        widget.item.vendor.isNotEmpty)
                      const SizedBox(height: 12),
                    if (widget.item.vendor.isNotEmpty)
                      _DetailRow(
                        label: 'Поставщик',
                        value: widget.item.vendor,
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (widget.item.receiptFileId.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined, color: _brand),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Чек прикреплён к расходу',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: _openReceipt,
                      child: const Text('Открыть'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить расход?'),
        content: Text('«${widget.item.title}» будет удалён из объекта.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.repository.delete(widget.item.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final updated = await showModalBottomSheet<RemoteCostItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateExpenseSheet(
        projectId: widget.item.projectId,
        repository: widget.repository,
        fileRepository: widget.fileRepository,
        initial: widget.item,
      ),
    );
    if (mounted && updated != null) Navigator.of(context).pop(updated);
  }

  Future<void> _openReceipt() async {
    try {
      final files = await widget.fileRepository.list(widget.item.projectId);
      RemoteProjectFile? receipt;
      for (final file in files) {
        if (file.id == widget.item.receiptFileId) {
          receipt = file;
          break;
        }
      }
      if (!mounted) return;
      if (receipt == null) {
        _toast(context, 'Прикреплённый файл больше недоступен');
        return;
      }
      widget.onOpenFile(receipt);
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    }
  }
}

class _ProjectForm extends StatefulWidget {
  const _ProjectForm({
    required this.repository,
    required this.fileRepository,
    this.initial,
  });

  final ProjectRepository repository;
  final ProjectFileRepository fileRepository;
  final RemoteProject? initial;

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

  bool get _editing => widget.initial != null;
  bool get _archived => widget.initial?.status == 'archived';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _name.text = initial.name;
    _address.text = initial.address;
    final parsedStartDate = DateTime.tryParse(initial.startDate);
    if (parsedStartDate != null) _startDate = parsedStartDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        centerTitle: true,
        title: Text(
          _editing ? 'Изменить объект' : 'Новый объект',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 104),
        children: [
          if (_editing && !_archived) ...[
            const Text(
              'Фото объекта',
              style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
            ),
            const SizedBox(height: 8),
            if (widget.initial!.coverFileId.isNotEmpty && _coverPath == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Текущее фото сохранится, если не выбрать новое.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            _ProjectCoverPicker(
              path: _coverPath,
              busy: _busy,
              emptyTitle: 'Заменить фото объекта',
              onPick: _pickCover,
              onRemove: () => setState(() {
                _coverPath = null;
                _coverName = null;
              }),
            ),
            const SizedBox(height: 22),
          ] else ...[
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
          ],
          const Text(
            'Название объекта',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Например: Дом в Кок-Жаре',
              prefixIcon: Icon(Icons.home_work_outlined),
              prefixIconColor: _brand,
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            'Адрес',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: _address,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Например: с. Кок-Жар, ул. Центральная, 10',
              prefixIcon: Icon(Icons.location_on_outlined),
              prefixIconColor: _brand,
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            'Дата начала',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 7),
          InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: _busy ? null : _pickStartDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_today_outlined),
                prefixIconColor: _brand,
              ),
              child: Text(
                _displayLongDate(_startDate),
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
          if (_editing) ...[
            const SizedBox(height: 26),
            OutlinedButton.icon(
              onPressed: _busy ? null : (_archived ? _restore : _archive),
              icon: Icon(
                _archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              label: Text(
                _archived ? 'Восстановить объект' : 'Архивировать объект',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _warning,
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: _warning),
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
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
                : Text(_editing ? 'Сохранить изменения' : 'Создать объект'),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCover() async {
    try {
      final selected = await FilePicker.pickFile(type: FileType.image);
      if (!mounted || selected == null) return;
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
    final today = DateTime.now();
    final firstDate = _startDate.isBefore(DateTime(2000))
        ? _startDate
        : DateTime(2000);
    final lastDate = _startDate.isAfter(today) ? _startDate : today;
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (selected != null && mounted) setState(() => _startDate = selected);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название объекта');
      return;
    }
    // Бюджет больше не запрашивается в форме, но при редактировании
    // сохраняется в модели, чтобы скрытие поля не затирало данные объекта.
    final budget = _editing ? widget.initial!.budgetAmount : 0.0;
    final currency = _editing ? widget.initial!.currency : 'KGS';
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_editing) {
        final updated = await widget.repository.updateProject(
          projectId: widget.initial!.id,
          name: name,
          address: _address.text.trim(),
          startDate: _apiDate(_startDate),
          status: widget.initial!.status,
          budgetAmount: budget,
          currency: currency,
        );
        final coverPath = _coverPath;
        if (coverPath != null) {
          try {
            final uploaded = await widget.fileRepository.upload(
              projectId: widget.initial!.id,
              kind: 'project_cover',
              filePath: coverPath,
              fileName: _coverName ?? 'project-cover.jpg',
            );
            if (uploaded.id.isEmpty) {
              throw const ApiException(500, 'Сервер не вернул файл обложки');
            }
          } catch (error) {
            if (mounted) {
              setState(
                () => _error =
                    'Объект сохранён, но фото не заменено: ${_errorText(error)}',
              );
            }
            return;
          }
        }
        if (mounted) Navigator.of(context).pop(updated);
      } else {
        final coverPath = _coverPath;
        if (coverPath == null) {
          await widget.repository.createProject(
            name: name,
            address: _address.text.trim(),
            startDate: _apiDate(_startDate),
            budgetAmount: budget,
            currency: currency,
          );
        } else {
          await widget.repository.createProjectWithCover(
            name: name,
            address: _address.text.trim(),
            startDate: _apiDate(_startDate),
            filePath: coverPath,
            fileName: _coverName ?? 'project-cover.jpg',
            budgetAmount: budget,
            currency: currency,
          );
        }
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Архивировать объект?'),
        content: const Text(
          'Объект исчезнет из активного списка, но его данные сохранятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Архивировать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.deleteProject(widget.initial!.id);
      if (mounted) Navigator.of(context).pop(widget.initial);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final restored = await widget.repository.updateProject(
        projectId: widget.initial!.id,
        name: widget.initial!.name,
        address: widget.initial!.address,
        startDate: widget.initial!.startDate,
        status: 'active',
        budgetAmount: widget.initial!.budgetAmount,
        currency: widget.initial!.currency,
      );
      if (mounted) Navigator.of(context).pop(restored);
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
    this.emptyTitle = 'Добавить фото объекта',
  });

  final String? path;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final String emptyTitle;

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
                    backgroundColor: _brand,
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
      borderRadius: BorderRadius.circular(13),
      onTap: busy ? null : onPick,
      child: CustomPaint(
        painter: _DashedOutlinePainter(color: _line, radius: 13),
        child: Container(
          height: 126,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2EF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _brand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emptyTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Будет обложкой в списке объектов',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedOutlinePainter extends CustomPainter {
  const _DashedOutlinePainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );

    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 8) {
        final end = distance + 5 < metric.length
            ? distance + 5
            : metric.length;
        canvas.drawPath(metric.extractPath(distance, end), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedOutlinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
