part of '../online_prorab_redesign.dart';

class _CreateExpenseSheet extends StatefulWidget {
  const _CreateExpenseSheet({
    required this.projectId,
    required this.repository,
    required this.fileRepository,
    this.initial,
  });
  final String projectId;
  final CostItemRepository repository;
  final ProjectFileRepository fileRepository;
  final RemoteCostItem? initial;

  @override
  State<_CreateExpenseSheet> createState() => _CreateExpenseSheetState();
}

class _CreateExpenseSheetState extends State<_CreateExpenseSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  String _category = 'materials';
  String _currency = 'KGS';
  DateTime _spentAt = DateTime.now();
  PlatformFile? _receiptFile;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _title.text = initial.title;
    _amount.text = initial.amount.toStringAsFixed(2);
    _vendor.text = initial.vendor;
    _category = initial.category;
    _currency = initial.currency;
    final spentAt = DateTime.tryParse(initial.spentAt);
    if (spentAt != null) _spentAt = spentAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _vendor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null ? 'Добавить расход' : 'Изменить расход',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Название',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Например: Цемент М500',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Сумма',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amount,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  suffixText: _currency == 'KGS' ? 'сом' : _currency,
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Категория',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'materials',
                    child: Text('Материалы'),
                  ),
                  DropdownMenuItem(value: 'labor', child: Text('Работа')),
                  DropdownMenuItem(
                    value: 'delivery',
                    child: Text('Доставка'),
                  ),
                  DropdownMenuItem(value: 'tools', child: Text('Инструменты')),
                  DropdownMenuItem(value: 'other', child: Text('Другое')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(
                          () => _category = value ?? 'other',
                        ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Чек',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickReceipt,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(
                  _receiptFile == null
                      ? (widget.initial?.receiptFileId.isNotEmpty ?? false)
                          ? 'Заменить прикреплённый чек'
                          : 'Прикрепить фото или PDF'
                      : _receiptFile!.name,
                ),
              ),
              if (_receiptFile != null) ...[
                const SizedBox(height: 6),
                Text(
                  _fileSize(_receiptFile!.lengthSync() ?? 0),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Поставщик',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _vendor,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Например: СтройМаркет',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Валюта',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.currency_exchange_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'KGS', child: Text('Сом (KGS)')),
                  DropdownMenuItem(value: 'USD', child: Text('Доллар (USD)')),
                  DropdownMenuItem(value: 'KZT', child: Text('Тенге (KZT)')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(
                          () => _currency = value ?? 'KGS',
                        ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Дата',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: _busy ? null : _pickSpentAt,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _displayDate(_spentAt),
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
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
                    : Text(
                        widget.initial == null
                            ? 'Сохранить расход'
                            : 'Сохранить изменения',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSpentAt() async {
    final today = DateTime.now();
    final firstDate = _spentAt.isBefore(DateTime(2000))
        ? _spentAt
        : DateTime(2000);
    final lastDate = _spentAt.isAfter(today) ? _spentAt : today;
    final selected = await showDatePicker(
      context: context,
      initialDate: _spentAt,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (selected != null && mounted) setState(() => _spentAt = selected);
  }

  Future<void> _pickReceipt() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      if (!mounted || result.isEmpty) return;
      final file = result.single;
      if (file.path == null || file.path!.isEmpty) {
        _toast(context, 'Выбранный файл недоступен');
        return;
      }
      setState(() => _receiptFile = file);
    } catch (_) {
      if (mounted) _toast(context, 'Не удалось выбрать чек');
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (_title.text.trim().isEmpty ||
        amount == null ||
        !_isValidMoney(amount, allowZero: false)) {
      _toast(context, 'Введите название и корректную сумму');
      return;
    }
    setState(() => _busy = true);
    try {
      final initial = widget.initial;
      var item = initial == null
          ? await widget.repository.create(
              projectId: widget.projectId,
              title: _title.text.trim(),
              amount: amount,
              spentAt: _apiDate(_spentAt),
              category: _category,
              currency: _currency,
              vendor: _vendor.text.trim(),
            )
          : await widget.repository.update(
              costItemId: initial.id,
              title: _title.text.trim(),
              amount: amount,
              spentAt: _apiDate(_spentAt),
              category: _category,
              currency: _currency,
              vendor: _vendor.text.trim(),
              receiptFileId: initial?.receiptFileId,
            );
      final receiptFile = _receiptFile;
      if (receiptFile != null) {
        final path = receiptFile.path;
        if (path == null || path.isEmpty) {
          throw const ApiException(400, 'Выбранный чек недоступен');
        }
        try {
          final uploaded = await widget.fileRepository.upload(
            projectId: widget.projectId,
            kind: 'receipt',
            filePath: path,
            fileName: receiptFile.name,
          );
          item = await widget.repository.update(
            costItemId: item.id,
            title: item.title,
            amount: item.amount,
            spentAt: item.spentAt,
            category: item.category,
            currency: item.currency,
            vendor: item.vendor,
            receiptFileId: uploaded.id,
          );
        } catch (error) {
          if (mounted) {
            _toast(
              context,
              'Расход сохранён, но чек не прикреплён: ${_errorText(error)}',
            );
            Navigator.of(context).pop(item);
          }
          return;
        }
      }
      if (mounted) Navigator.of(context).pop(item);
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
