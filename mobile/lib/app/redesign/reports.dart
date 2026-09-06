part of '../online_prorab_redesign.dart';

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({
    required this.reports,
    required this.onAdd,
    required this.onDelete,
    required this.onEdit,
  });

  final List<RemoteDailyReport> reports;
  final VoidCallback? onAdd;
  final ValueChanged<RemoteDailyReport>? onDelete;
  final ValueChanged<RemoteDailyReport>? onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        _PageHeader(
          title: 'Отчёты',
          subtitle: '${reports.length} отчётов по объекту',
          action: onAdd == null
              ? null
              : IconButton.filled(
                  tooltip: 'Добавить отчёт',
                  style: IconButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                ),
        ),
        const SizedBox(height: 16),
        if (reports.isEmpty)
          const _EmptyCard(
            icon: Icons.assignment_outlined,
            title: 'Отчётов пока нет',
            message: 'Добавьте первый ежедневный отчёт о ходе работ.',
          )
        else
          ...reports.map(
            (report) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReportCard(
                report: report,
                onDelete: onDelete == null ? null : () => onDelete!(report),
                onEdit: onEdit == null ? null : () => onEdit!(report),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    this.onDelete,
    this.onEdit,
  });

  final RemoteDailyReport report;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.assignment_outlined, color: _brand),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      report.reportDate.isEmpty
                          ? 'Дата не указана'
                          : _displayIsoDate(report.reportDate),
                      style: const TextStyle(
                        color: _brand,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${report.workersCount} работников',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'Удалить отчёт',
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: _muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                report.summary.isEmpty ? 'Без описания' : report.summary,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              if (report.issues.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: _warningSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Замечания: ${report.issues}',
                    style: const TextStyle(color: _warning, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({
    required this.projectId,
    required this.repository,
    this.initial,
  });

  final String projectId;
  final DailyReportRepository repository;
  final RemoteDailyReport? initial;

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  final _summary = TextEditingController();
  final _workers = TextEditingController(text: '0');
  final _issues = TextEditingController();
  DateTime _reportDate = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _summary.text = initial.summary;
    _workers.text = initial.workersCount.toString();
    _issues.text = initial.issues;
    final reportDate = DateTime.tryParse(initial.reportDate);
    if (reportDate != null) _reportDate = reportDate;
  }

  @override
  void dispose() {
    _summary.dispose();
    _workers.dispose();
    _issues.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          widget.initial == null ? 'Новый отчёт' : 'Изменить отчёт',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            'Дата отчёта',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: _busy ? null : _pickReportDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(
                _displayDate(_reportDate),
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Что сделано',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _summary,
            enabled: !_busy,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Опишите результат работ за день',
              prefixIcon: Icon(Icons.description_outlined),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Количество работников',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _workers,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.groups_outlined),
              hintText: '0',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Замечания',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _issues,
            enabled: !_busy,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Что требует внимания',
              prefixIcon: Icon(Icons.warning_amber_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
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
                        ? 'Сохранить отчёт'
                        : 'Сохранить изменения',
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickReportDate() async {
    final today = DateTime.now();
    final firstDate = _reportDate.isBefore(DateTime(2000))
        ? _reportDate
        : DateTime(2000);
    final lastDate = _reportDate.isAfter(today) ? _reportDate : today;
    final selected = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (selected != null && mounted) setState(() => _reportDate = selected);
  }

  Future<void> _save() async {
    final summary = _summary.text.trim();
    final workers = int.tryParse(_workers.text.trim());
    if (summary.isEmpty || workers == null || workers < 0) {
      setState(() => _error = 'Введите описание и корректное число работников');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final initial = widget.initial;
      final report = initial == null
          ? await widget.repository.create(
              projectId: widget.projectId,
              summary: summary,
              workersCount: workers,
              issues: _issues.text.trim(),
              reportDate: _apiDate(_reportDate),
            )
          : await widget.repository.update(
              reportId: initial.id,
              summary: summary,
              workersCount: workers,
              issues: _issues.text.trim(),
              reportDate: _apiDate(_reportDate),
            );
      if (mounted) Navigator.of(context).pop(report);
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
