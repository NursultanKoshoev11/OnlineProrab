import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:online_prorab/app/online_prorab_redesign.dart';

void main() {
  test('redesigned app can be constructed', () {
    expect(const OnlineProrabRedesignApp(), isA<Widget>());
  });
  testWidgets('login fits a small screen and validates an incomplete phone', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const OnlineProrabRedesignApp());
    await tester.pumpAndSettle();
    expect(find.text('Получить код'), findsOneWidget);
    await tester.tap(find.text('Получить код'));
    await tester.pumpAndSettle();
    expect(find.text('Введите корректный номер телефона'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
