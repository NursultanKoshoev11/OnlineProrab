import 'package:flutter/services.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _stroyGreen = PdfColor(0.031, 0.478, 0.239);
const _stroyInk = PdfColor(0.067, 0.094, 0.082);
const _stroyMuted = PdfColor(0.38, 0.44, 0.41);
const _stroyLine = PdfColor(0.88, 0.91, 0.89);
const _stroySoft = PdfColor(0.90, 0.96, 0.92);

Future<Uint8List> buildExpenseReportPdf({
  required RemoteProject project,
  required Iterable<RemoteCostItem> costs,
  DateTime? generatedAt,
}) async {
  final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
  final font = pw.Font.ttf(fontData);
  final items = costs.toList()
    ..sort((left, right) {
      final leftDate = DateTime.tryParse(left.spentAt) ?? DateTime(1900);
      final rightDate = DateTime.tryParse(right.spentAt) ?? DateTime(1900);
      final dateOrder = rightDate.compareTo(leftDate);
      if (dateOrder != 0) return dateOrder;
      return right.createdAt.compareTo(left.createdAt);
    });
  final totals = <String, double>{};
  for (final item in items) {
    final currency = _currency(item.currency);
    totals[currency] = (totals[currency] ?? 0) + item.amount;
  }

  final document = pw.Document(
    title: 'STROY - отчет по расходам',
    author: 'STROY',
    subject: project.name,
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final date = generatedAt ?? DateTime.now();
  final titleStyle = pw.TextStyle(
    font: font,
    fontSize: 22,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );
  final mutedStyle = pw.TextStyle(
    font: font,
    fontSize: 9,
    color: _stroyMuted,
  );
  final smallStyle = pw.TextStyle(font: font, fontSize: 8, color: _stroyInk);
  final boldStyle = pw.TextStyle(
    font: font,
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: _stroyInk,
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 30),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'STROY',
              style: pw.TextStyle(
                font: font,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _stroyGreen,
                letterSpacing: 1.2,
              ),
            ),
            pw.Text(
              'Автоматический отчёт по расходам',
              style: mutedStyle,
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _stroyLine)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('STROY', style: mutedStyle),
            pw.Text(
              'Страница ${context.pageNumber} из ${context.pagesCount}',
              style: mutedStyle,
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(18),
          decoration: const pw.BoxDecoration(
            color: _stroyGreen,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('ОТЧЁТ', style: titleStyle),
              pw.SizedBox(height: 5),
              pw.Text(
                project.name.trim().isEmpty ? 'Объект' : project.name.trim(),
                style: pw.TextStyle(
                  font: font,
                  fontSize: 13,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _stroyLine),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Column(
            children: [
              _metadataRow('Адрес', _fallback(project.address)),
              _metadataRow('Дата начала', _formatDate(project.startDate)),
              _metadataRow('Сформирован', _formatDateTime(date.toLocal())),
              _metadataRow('Расходов', '${items.length}'),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Общий итог',
          style: pw.TextStyle(
            font: font,
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: _stroyInk,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: const pw.BoxDecoration(
            color: _stroySoft,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Всего потрачено', style: boldStyle),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Text(
                  totals.isEmpty
                      ? _formatMoney(0, 'KGS')
                      : totals.entries
                          .map((entry) => _formatMoney(entry.value, entry.key))
                          .join('  •  '),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _stroyGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Детализация расходов',
          style: pw.TextStyle(
            font: font,
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: _stroyInk,
          ),
        ),
        pw.SizedBox(height: 8),
        if (items.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _stroyLine),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Text('Расходов пока нет.', style: mutedStyle),
          )
        else
          pw.Table(
            border: pw.TableBorder.all(color: _stroyLine, width: .6),
            columnWidths: const {
              0: pw.FixedColumnWidth(23),
              1: pw.FixedColumnWidth(60),
              2: pw.FlexColumnWidth(3.8),
              3: pw.FlexColumnWidth(1.3),
            },
            children: [
              _tableRow(
                const ['№', 'Дата', 'Расход / описание', 'Сумма'],
                font: font,
                header: true,
              ),
              ...items.asMap().entries.map(
                    (entry) => _tableRow(
                      [
                        '${entry.key + 1}',
                        _formatDate(entry.value.spentAt),
                        _expenseDetails(entry.value),
                        _formatMoney(entry.value.amount, entry.value.currency),
                      ],
                      font: font,
                    ),
                  ),
            ],
          ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Отчёт формируется автоматически из текущих расходов объекта и обновляется сразу после изменений.',
          style: smallStyle,
        ),
      ],
    ),
  );

  return document.save();
}

pw.TableRow _tableRow(
  List<String> values, {
  required pw.Font font,
  bool header = false,
}) {
  return pw.TableRow(
    decoration: header ? const pw.BoxDecoration(color: _stroyGreen) : null,
    children: values
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: pw.Text(
              value,
              maxLines: header ? 2 : 5,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                font: font,
                fontSize: header ? 7.2 : 7.5,
                fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: header ? PdfColors.white : _stroyInk,
              ),
            ),
          ),
        )
        .toList(),
  );
}

String _expenseDetails(RemoteCostItem item) {
  final title = _fallback(item.title);
  final description = item.description.trim();
  if (description.isEmpty) return title;
  return '$title\n$description';
}

pw.Widget _metadataRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 92,
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8, color: _stroyMuted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: const pw.TextStyle(
              fontSize: 8.5,
              color: _stroyInk,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

String _currency(String value) {
  final currency = value.trim().toUpperCase();
  return currency.isEmpty ? 'KGS' : currency;
}

String _fallback(String value) => value.trim().isEmpty ? '-' : value.trim();

String _formatDate(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return _fallback(value);
  return '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year}';
}

String _formatDateTime(DateTime value) {
  final date = _formatDate(value.toIso8601String());
  return '$date ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _formatMoney(double value, String currency) {
  final safe = value.isFinite ? value : 0;
  final cents = (safe.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final fraction = cents % 100;
  final groups = <String>[];
  for (var end = whole.length; end > 0; end -= 3) {
    final start = (end - 3).clamp(0, end);
    groups.insert(0, whole.substring(start, end));
  }
  final amount = fraction == 0
      ? groups.join(' ')
      : '${groups.join(' ')}.${fraction.toString().padLeft(2, '0')}';
  return '${safe < 0 ? '-' : ''}$amount ${_currency(currency)}';
}

String _categoryLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'materials':
      return 'Материалы';
    case 'labor':
      return 'Работа';
    case 'transport':
      return 'Транспорт';
    case 'equipment':
      return 'Техника';
    default:
      return 'Другое';
  }
}
