import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:z_calculator/main.dart';

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
    // v1.10 起结果区不再带 "=" 前缀（与历史行格式撞车），结果为独立大字行
    expect(find.text('14', skipOffstage: false), findsOneWidget);
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
    // v1.8 起 = 会把表达式提交到显示区纸带，历史面板中的条目需在面板内定位
    final inSheet = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.text('7+5 = 12'),
    );
    expect(inSheet, findsOneWidget);
    // 点击回填到输入框
    await tester.tap(inSheet);
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

  test('多项式求根：二重根 (2x+5)^2 不再发散为 NaN', () {
    final r = durandKerner([4, 20, 25]);
    expect(r.length, 2);
    expect(r[0].re, closeTo(-2.5, 1e-6));
    expect(r[1].re, closeTo(-2.5, 1e-6));
    expect(r[0].im.abs(), lessThan(1e-6));
    expect(r[1].im.abs(), lessThan(1e-6));
  });

  test('多项式求根：复根与三实根', () {
    final c = durandKerner([1, 0, 1]); // x^2+1 → ±i
    expect(c[0].re, closeTo(0, 1e-8));
    expect(c[1].re, closeTo(0, 1e-8));
    expect(c[0].im.abs(), closeTo(1, 1e-8));
    expect(c[1].im.abs(), closeTo(1, 1e-8));
    final t = durandKerner([1, -6, 11, -6]); // (x-1)(x-2)(x-3)
    expect(t[0].re, closeTo(1, 1e-8));
    expect(t[1].re, closeTo(2, 1e-8));
    expect(t[2].re, closeTo(3, 1e-8));
  });

  test('隐函数归一化：A=B 转为 A-(B)', () {
    expect(implicitEqSrc('x+y=1'), '(x+y) - (1)');
    expect(implicitEqSrc('x^2+y^2-25'), 'x^2+y^2-25');
  });
}
