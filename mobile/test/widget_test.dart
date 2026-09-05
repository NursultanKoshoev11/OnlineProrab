import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/app/online_prorab_redesign.dart';

void main() {
  test('redesigned app can be constructed', () {
    expect(const OnlineProrabRedesignApp(), isA<Widget>());
  });
}
