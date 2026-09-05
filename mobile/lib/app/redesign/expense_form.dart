part of '../online_prorab_redesign.dart';

class _CreateExpenseSheet extends StatefulWidget {
  const _CreateExpenseSheet({required this.project, required this.repository});
  final RemoteProject project;
  final CostItemRepository repository;

  @override
  State<_CreateExpenseSheet> createState() => _CreateExpenseSheetState();
}

class _CreateExpenseSheetState extends State<_CreateExpenseSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  String _category = 'materials';
  DateTime _spentAt = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _vendor.dispose();
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Добавить расход',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Сумма',
                suffixText: 'сом',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Категория'),
              items: const [
                DropdownMenuItem(value: 'materials', child: Text('Материалы')),
                DropdownMenuItem(value: 'work', child: Text('Работы')),
                DropdownMenuItem(value: 'equipment', child: Text('Техника')),
                DropdownMenuItem(value: 'delivery', child: Text('Доставка')),
                DropdownMenuItem(value: 'windows', child: Text('Окна')),
                DropdownMenuItem(value: 'electricity', child: Text('Электрика')),
                DropdownMenuItem(value: 'other', child: Text('Прочее')),
              ],
              onChanged: (value) => setState(() => _category = value ?? 'other'),
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickSpentAt,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Дата расхода',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(_displayDate(_spentAt)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _vendor,
              decoration: const InputDecoration(
                labelText: 'Поставщик (необязательно)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Сохранить расход'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSpentAt() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _spentAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selected != null && mounted) setState(() => _spentAt = selected);
  }

  String _displayDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  String _apiDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (_title.text.trim().isEmpty || amount == null || amount <= 0) {
      _toast(context, 'Введите название и корректную сумму');
      return;
    }
    setState(() => _busy = true);
    try {
      final item = await widget.repository.create(
        projectId: widget.project.id,
        title: _title.text.trim(),
        amount: amount,
        category: _category,
        currency: 'KGS',
        vendor: _vendor.text.trim(),
        spentAt: _apiDate(_spentAt),
      );
      if (mounted) Navigator.of(context).pop(item);
    } catch (error) {
      if (mounted) _toast(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
