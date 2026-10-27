import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_graph_calc/main.dart';

void main() {
  testWidgets('实时计算：输入即显示结果，无需按等号', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('2'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('×'));
    await tester.tap(find.text('4'));
    await tester.pump();
    // 2+3*4 = 14 应实时预览
    expect(find.text('= 14', skipOffstage: false), findsOneWidget);
  });

  testWidgets('计算历史：按 = 后记录，面板可查看与回填', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('7'));
    await tester.tap(find.text('+'));
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('='));
    await tester.pumpAndSettle();
    // 打开历史面板
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(find.text('7+5 = 12'), findsOneWidget);
    // 点击回填到输入框
    await tester.tap(find.text('7+5 = 12'));
    await tester.pumpAndSettle();
    expect(find.text('7+5'), findsWidgets);
  });

  testWidgets('图形页符号条：可插入特殊符号', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();
    // 符号条存在
    expect(find.text('√'), findsWidgets);
    expect(find.text('π'), findsWidgets);
    expect(find.text('sin('), findsWidgets);
    // 点击 √ 插入到第一条函数输入框
    final before = tester.widget<TextField>(find.byType(TextField).first).controller?.text ?? '';
    await tester.tap(find.text('√'));
    await tester.pump();
    final after = tester.widget<TextField>(find.byType(TextField).first).controller?.text ?? '';
    expect(after, contains('sqrt('));
    expect(after.length, greaterThan(before.length));
  });

  testWidgets('负 x 抛物线：a*x^2 在 x<0 处能求值', (tester) async {
    // 引擎层面验证负半支不再返回 NaN
    expect(evaluate('a*x^2', -2, {'a': 1}, AngleMode.rad, 0), 4);
    expect(evaluate('a*x^2', -3, {'a': 2}, AngleMode.rad, 0), 18);
    expect(evaluate('x^2', -4, {}, AngleMode.rad, 0), 16);
  });
}
