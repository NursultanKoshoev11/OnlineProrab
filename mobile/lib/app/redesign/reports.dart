part of '../online_prorab_redesign.dart';

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({required this.project, required this.costs});

  final RemoteProject project;
  final List<RemoteCostItem> costs;

  String get _fingerprint => costs
      .map(
        (item) =>
            '${item.id}:${item.amount}:${item.spentAt}:${item.title}:${item.description}:${item.receiptFileId}',
      )
      .join('|');

  String get _fileName {
    final name = project.name
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-ЯёЁ_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return 'STROY_${name.isEmpty ? 'report' : name}.pdf';
  }

  Future<Uint8List> _build(PdfPageFormat _) {
    return buildExpenseReportPdf(project: project, costs: costs);
  }

  Future<void> _share(BuildContext context) async {
    try {
      final bytes = await _build(PdfPageFormat.a4);
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    } catch (_) {
      if (context.mounted) _toast(context, 'Не удалось поделиться PDF');
    }
  }

  Future<void> _save(BuildContext context) async {
    try {
      final bytes = await _build(PdfPageFormat.a4);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      _toast(context, 'PDF сохранён');
      await OpenFilex.open(file.path);
    } catch (_) {
      if (context.mounted) _toast(context, 'Не удалось сохранить PDF');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _moneyTotals(costs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        children: [
          const _PageHeader(
            title: 'Отчёт',
            subtitle: 'Один PDF по текущим расходам объекта',
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _brandSoft,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: _brand,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Автоматический PDF',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${costs.length} ${costs.length == 1 ? 'расход' : 'расходов'}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ReportMetric(
                          label: 'Общий итог',
                          value: total,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _save(context),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Сохранить'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _share(context),
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('Отправить'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Предпросмотр PDF',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: PdfPreview(
                key: ValueKey(_fingerprint),
                build: _build,
                pdfFileName: _fileName,
                allowSharing: true,
                allowPrinting: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                maxPageWidth: 700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
