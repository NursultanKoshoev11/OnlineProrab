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
  DateTime _spentAt = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
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
              const Text(
                'Добавить расход',
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: '0',
                  suffixText: 'сом',
                  prefixIcon: Icon(Icons.payments_outlined),
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
                onTap: _pickSpentAt,
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
                    : const Text('Сохранить расход'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSpentAt() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _spentAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) setState(() => _spentAt = selected);
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
