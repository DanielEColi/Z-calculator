import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:z_calculator/main.dart';

void main() {
  // 复现真机场景：先聚焦函数输入框并输入文本，再点符号条
  testWidgets('聚焦输入框后点符号条仍可插入', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'x+y=1');
    await tester.pumpAndSettle();

    // 点 π 符号
    await tester.tap(find.text('π'));
    await tester.pumpAndSettle();

    final ctrl = tester.widget<TextField>(field).controller!;
    // ignore: avoid_print
    print('插入后文本 = "${ctrl.text}"');
    expect(ctrl.text, 'x+y=1pi');
  });
}
