import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/app/online_prorab_redesign.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';

RemoteCostItem cost({
  required String title,
  required String spentAt,
  String vendor = '',
}) => RemoteCostItem(
  id: '$title-$spentAt',
  projectId: 'project-1',
  title: title,
  amount: 100,
  category: 'other',
  currency: 'KGS',
  vendor: vendor,
  spentAt: spentAt,
);

void main() {
  final now = DateTime(2026, 9, 6);

  test('parses expense name and explicit month/year from Russian voice query', () {
    final query = parseExpenseSearchQuery(
      'Сколько потратили на окна за май 2026?',
      now: now,
    );

    expect(query.month, 5);
    expect(query.year, 2026);
    expect(query.term, 'окна');
    expect(
      query.matches(cost(title: 'Окна первый этаж', spentAt: '2026-05-20')),
      isTrue,
    );
    expect(
      query.matches(cost(title: 'Окна первый этаж', spentAt: '2026-06-01')),
      isFalse,
    );
  });

  test('uses current year when month is spoken without a year', () {
    final query = parseExpenseSearchQuery(
      'Покажи расходы на электрику за сентябрь',
      now: now,
    );

    expect(query.term, 'электрику');
    expect(query.month, 9);
    expect(query.year, 2026);
    expect(
      query.matches(cost(title: 'Электрику оплатили', spentAt: '2026-09-02')),
      isTrue,
    );
  });

  test('keeps a material name as free text search', () {
    final query = parseExpenseSearchQuery('Покажи расходы на цемент', now: now);

    expect(query.term, 'цемент');
    expect(
      query.matches(cost(title: 'Цемент М500', spentAt: '2026-09-01')),
      isTrue,
    );
  });

  test('legacy supplier text can still be found', () {
    final query = parseExpenseSearchQuery(
      'Найди расходы СтройМаркет',
      now: now,
    );

    expect(query.term, 'строймаркет');
    expect(
      query.matches(
        cost(
          title: 'Кабель',
          spentAt: '2026-09-02',
          vendor: 'СтройМаркет Бишкек',
        ),
      ),
      isTrue,
    );
  });
}
