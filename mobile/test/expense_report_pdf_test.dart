import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/features/reports/expense_report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a Cyrillic PDF with current project expenses', () async {
    final project = RemoteProject(
      id: 'project-1',
      name: 'Дом на Иссык-Куле',
      address: 'Чолпон-Ата',
      status: 'active',
      coverFileId: '',
      startDate: '2026-09-01',
    );
    final costs = [
      RemoteCostItem(
        id: 'cost-1',
        projectId: project.id,
        title: 'Цемент',
        amount: 12500,
        category: 'materials',
        currency: 'KGS',
        vendor: 'Поставщик',
        spentAt: '2026-09-06',
      ),
    ];

    final bytes = await buildExpenseReportPdf(
      project: project,
      costs: costs,
      generatedAt: DateTime(2026, 9, 7, 10, 30),
    );

    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
}
