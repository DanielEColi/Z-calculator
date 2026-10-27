import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:z_calculator/main.dart';

void main() {
  test('参数提取：保留原始大小写，A 与 a 是不同参数', () {
    expect(collectParams('A*x^2'), {'A'});
    expect(collectParams('A*x + a'), {'A', 'a'});
    // 大写 E 是独立参数，小写 e 是自然常数
    expect(collectParams('E*x + e'), {'E'});
    // x / y / pi / 函数名不作为参数
    expect(collectParams('sin(x) + y + pi'), <String>{});
    // 多参数
    expect(collectParams('a*x^2 + b*x + c'), {'a', 'b', 'c'});
  });

  testWidgets('参数面板：多参数按两列网格排列且不溢出页面', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    // 输入含 4 个参数的表达式
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'a*x^2+b*x+c');
    await tester.pumpAndSettle();

    // 4 个参数都出现
    for (final k in ['a', 'b', 'c']) {
      expect(find.text(k), findsWidgets, reason: '参数 $k 应显示');
    }

    // 所有参数控件都在屏幕宽度内（不超出页面外）
    final screenW = tester.getSize(find.byType(MaterialApp)).width;
    for (final k in ['a', 'b', 'c']) {
      final box = tester.getRect(find.text(k).first);
      expect(box.left, greaterThanOrEqualTo(0), reason: '参数 $k 不应超出左边界');
      expect(box.right, lessThanOrEqualTo(screenW + 0.5), reason: '参数 $k 不应超出右边界');
    }

    // 无 RenderFlex 溢出
    expect(tester.takeException(), isNull);
  });

  testWidgets('隐函数切换：点击模式按钮自动补 =0 / 去掉 =0', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'x+y');
    await tester.pumpAndSettle();

    // 点击模式切换按钮（y = / 0 =）
    final modeBtn = find.byIcon(Icons.show_chart).first;
    await tester.tap(modeBtn);
    await tester.pumpAndSettle();

    var ctrl = tester.widget<TextField>(field).controller!;
    expect(ctrl.text, 'x+y=0', reason: '切到隐式应自动补 =0');

    // 再点一次切回显式
    await tester.tap(find.byIcon(Icons.blur_circular));
    await tester.pumpAndSettle();
    ctrl = tester.widget<TextField>(field).controller!;
    expect(ctrl.text, 'x+y', reason: '切回显式应去掉 =0');
  });

  testWidgets('隐函数切换：不含 y 的表达式改写为 y-(f)=0 并可还原', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'x^2-1');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.show_chart).first);
    await tester.pumpAndSettle();
    var ctrl = tester.widget<TextField>(field).controller!;
    expect(ctrl.text, 'y-(x^2-1)=0', reason: '隐式应改写为 y-(f)=0');

    await tester.tap(find.byIcon(Icons.blur_circular).first);
    await tester.pumpAndSettle();
    ctrl = tester.widget<TextField>(field).controller!;
    expect(ctrl.text, 'x^2-1', reason: '切回显式应还原为原表达式');
  });

  testWidgets('隐函数切换：空表达式填入示例并给出提示', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    await tester.enterText(field, '');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.show_chart).first);
    await tester.pumpAndSettle();

    final ctrl = tester.widget<TextField>(find.byType(TextField).first).controller!;
    expect(ctrl.text, 'x^2+y^2=9');
    expect(find.textContaining('隐式示例'), findsOneWidget);
  });

  testWidgets('符号条：字号与点击目标放大', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    final pi = tester.widget<Text>(find.text('π').first);
    expect(pi.style?.fontSize, greaterThanOrEqualTo(19));

    // 点击目标（宽）不小于 46
    final box = tester.getSize(find.ancestor(
      of: find.text('π').first,
      matching: find.byType(Container),
    ).first);
    expect(box.width, greaterThanOrEqualTo(46));
    expect(box.height, greaterThanOrEqualTo(40));
  });
}
