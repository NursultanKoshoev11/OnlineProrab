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

  @override
  Widget build(BuildContext context) {
    final total = _moneyTotals(costs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        children: [
          const _PageHeader(title: 'Отчёт'),
          const SizedBox(height: 8),
          _ReportMetric(label: 'Общий итог', value: total),
          const SizedBox(height: 6),
          Expanded(
            child: costs.isEmpty
                ? Card(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Добавьте хотя бы один расход, чтобы открыть отчёт.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted),
                        ),
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: PdfPreview(
                      key: ValueKey(_fingerprint),
                      build: _build,
                      pdfFileName: _fileName,
                      allowSharing: true,
                      allowPrinting: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
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
