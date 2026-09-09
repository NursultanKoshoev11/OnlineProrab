import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:online_prorab/main.dart' as app;

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(finder, findsOneWidget);
}

Future<void> waitUntilGone(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (finder.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(finder, findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('server connected app flow', (tester) async {
    app.main();
    await tester.pump(const Duration(milliseconds: 500));
    await waitFor(tester, find.text('Получить код'));

    final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(
      7,
    );
    final phone = '+996700$suffix';
    await tester.enterText(find.byType(TextField).first, phone);
    await tester.tap(find.text('Получить код'));
    await waitFor(tester, find.textContaining('Код для разработки:'));
    final devText = tester
        .widget<Text>(find.textContaining('Код для разработки:'))
        .data!;
    final code = RegExp(r'\d{6}').firstMatch(devText)!.group(0)!;
    await tester.enterText(find.byType(TextField).at(1), code);
    await tester.tap(find.text('Войти'));
    await waitFor(tester, find.byTooltip('Добавить объект'));

    await tester.tap(find.byTooltip('Добавить объект'));
    await waitFor(tester, find.text('Новый объект'));
    final projectName = 'UI test ${DateTime.now().millisecondsSinceEpoch}';
    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Например: Дом в Кок-Жаре',
    );
    final addressField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Например: с. Кок-Жар, ул. Центральная, 10',
    );
    expect(nameField, findsOneWidget);
    expect(addressField, findsOneWidget);
    await tester.enterText(nameField, projectName);
    await tester.enterText(addressField, 'Тестовый адрес, 1');

    final datePicker = find.ancestor(
      of: find.byType(InputDecorator),
      matching: find.byType(InkWell),
    );
    expect(datePicker, findsOneWidget);
    await tester.tap(datePicker);
    await tester.pump(const Duration(milliseconds: 500));
    final dateDialog = find.byType(Dialog);
    if (dateDialog.evaluate().isNotEmpty) {
      final dialogButtons = find.byType(TextButton);
      if (dialogButtons.evaluate().isNotEmpty) {
        await tester.tap(dialogButtons.last);
      }
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать объект'));
    await waitUntilGone(tester, find.text('Новый объект'));
    await waitFor(tester, find.text(projectName));
    final editButton = find.byTooltip('Изменить объект');
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await waitFor(tester, find.text('Изменить объект'));
    await waitFor(tester, find.text('Архивировать объект'));
    await tester.scrollUntilVisible(
      find.text('Архивировать объект'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Архивировать объект'));
    await waitFor(tester, find.text('Архивировать'));
    await tester.tap(find.text('Архивировать'));
    await waitUntilGone(tester, find.text('Изменить объект'));
    await waitFor(tester, find.byTooltip('Добавить объект'));

    await tester.tap(find.text('Архивные объекты'));
    await waitFor(tester, find.text(projectName));
    final archivedEditButton = find.byTooltip('Изменить объект');
    expect(archivedEditButton, findsOneWidget);
    await tester.tap(archivedEditButton);
    await waitFor(tester, find.text('Изменить объект'));
    await waitFor(tester, find.text('Восстановить объект'));
    await tester.scrollUntilVisible(
      find.text('Восстановить объект'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Восстановить объект'));
    await waitUntilGone(tester, find.text('Изменить объект'));
    await waitFor(tester, find.text('Архивные объекты'));
    await tester.tap(find.text('Архивные объекты'));
    await waitFor(tester, find.text(projectName));

    await tester.tap(find.text(projectName));
    await waitFor(tester, find.text('Обзор объекта'));
    await tester.tap(find.byTooltip('Дополнительно'));
    await waitFor(tester, find.text('Обновить'));
    await tester.tap(find.text('Обновить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Расходы').last);
    await tester.pumpAndSettle();
    expect(find.text('Расходы'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('Отчёты').last);
    await tester.pumpAndSettle();
    expect(find.text('Отчёты'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('Ещё'));
    await waitFor(tester, find.text('Разделы'));

    await tester.tap(find.text('Техподдержка'));
    await waitFor(tester, find.text('Отправить обращение'));
    final supportFields = find.byType(TextField);
    expect(supportFields, findsNWidgets(2));
    await tester.enterText(supportFields.first, 'Проверка поддержки');
    await tester.enterText(
      supportFields.last,
      'Тест сохранения обращения без API-ключей',
    );
    await tester.tap(find.text('Отправить обращение'));
    await waitFor(tester, find.textContaining('Обращение сохранено'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('Разделы'));

    await tester.tap(find.text('Команда'));
    await waitFor(tester, find.byType(FloatingActionButton));
    await tester.tap(find.byType(FloatingActionButton));
    await waitFor(tester, find.byType(AlertDialog));
    await tester.tap(find.text('Отмена'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('Разделы'));

    await tester.tap(find.text('Подписка и доступ'));
    await waitFor(tester, find.text('Подписка'));
    await tester.tap(find.text('Free'));
    await tester.tap(find.text('Team'));
    await tester.tap(find.text('Optima Bank'));
    final subscriptionLists = find.byType(ListView);
    await tester.drag(subscriptionLists.last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('Показать QR-код'));
    await tester.tap(find.text('Показать QR-код'));
    await waitFor(tester, find.text('QR-код готов'));
    await tester.tap(find.byTooltip('Закрыть'));
    await waitFor(tester, find.text('Разделы'));
    await tester.tap(find.text('Отчёт расходов'));
    await waitFor(tester, find.text('Отчёты'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Профиль').last);
    await waitFor(tester, find.text('Выйти'));
    await tester.tap(find.text('Выйти'));

    // Unmount the app so long-lived realtime streams are closed before tearDownAll.
    runApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
