import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:online_prorab/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline project, expenses, reports, team and archive flows', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Не удалось загрузить'), findsNothing);
      await binding.takeScreenshot(
        '${const String.fromEnvironment('SCREENSHOT_PREFIX')}$name',
      );
    }

    Finder hint(String text) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == text,
    );
    Future<void> tapText(String text) async {
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Future<void> waitFor(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(finder, findsOneWidget);
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    expect(find.text('Дом на Иссык-Куле'), findsOneWidget);
    await capture('01-projects');
    await tester.enterText(hint('Поиск объектов'), 'zzzz');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await capture('02-empty-search');
    await tester.tap(find.byTooltip('Очистить поиск объектов'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tapText('Архивные объекты');
    await capture('02b-archive');
    await waitFor(find.text('Ремонт квартиры'));
    await tapText('Архивные объекты');

    await tapText('Дом на Иссык-Куле');
    expect(find.text('Обзор объекта'), findsOneWidget);
    await capture('03-overview');
    await tapText('Расходы');
    expect(find.text('Окна'), findsOneWidget);
    await capture('04-expenses');
    await tester.enterText(hint('Поиск расходов'), 'Цемент');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Цемент и песок'), findsOneWidget);
    expect(find.text('Окна'), findsNothing);
    await tester.tap(find.byTooltip('Очистить поиск расходов'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await tapText('Добавить расход');
    await capture('05-expense-form');
    await tester.enterText(hint('Например: Цемент М500'), 'Проверка AVD');
    await tester.enterText(hint('0'), '1250');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tapText('Сохранить расход');
    expect(find.text('Проверка AVD'), findsOneWidget);

    await tapText('Отчёты');
    await tester.pump(const Duration(seconds: 3));
    await capture('06-report');
    await tapText('Ещё');
    await capture('07-more');
    await tapText('Команда');
    expect(find.text('Команда объекта'), findsOneWidget);
    await capture('08-team');
    await back();
    await back();

    await tester.tap(find.byTooltip('Добавить объект'));
    await tester.pumpAndSettle();
    await capture('09-project-form');
    await tester.enterText(hint('Например: Дом в Кок-Жаре'), 'Объект AVD');
    await tester.enterText(
      hint('Например: с. Кок-Жар, ул. Центральная, 10'),
      'Бишкек, тестовый адрес',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Создать объект'));
    await tapText('Создать объект');
    await tester.enterText(hint('Поиск объектов'), 'Объект AVD');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Объект AVD'),
      findsOneWidget,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Изменить объект'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Архивировать объект'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tapText('Архивировать объект');
    await tapText('Архивировать');
    await tapText('Архивные объекты');
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Объект AVD'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Изменить объект'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Восстановить объект'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tapText('Восстановить объект');
    await tester.tap(find.byTooltip('Очистить поиск объектов'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tapText('Архивные объекты');
    await capture('10-projects-final');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
