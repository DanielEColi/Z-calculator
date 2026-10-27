import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:z_calculator/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  _dataTests();

  testWidgets('历史持久化：重启后历史与 ans 自动恢复', (tester) async {
    SharedPreferences.setMockInitialValues({
      'calc_history': jsonEncode([
        ['1+1', '2'],
        ['7*6', '42'],
      ]),
      'calc_tape': jsonEncode([
        ['1+1', '2'],
      ]),
      'calc_ans': 42.0,
    });

    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.pumpAndSettle();

    // ans 已恢复
    expect(find.text('ans = 42'), findsOneWidget);

    // 历史面板中出现持久化记录
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    // 纸带行与历史面板各出现一次
    expect(find.text('1+1 = 2'), findsWidgets);
    expect(find.text('7*6 = 42'), findsWidgets);
  });

  testWidgets('图形页函数与参数可持久化恢复', (tester) async {
    SharedPreferences.setMockInitialValues({
      'graph_fns': jsonEncode([
        ['x^2+y^2=9', 'implicit'],
        ['a*x', 'y'],
      ]),
    });

    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    // 隐式函数被恢复（模式按钮显示 F(x,y)=0）
    expect(find.text('F(x,y)=0'), findsOneWidget);
    // 参数 a 从表达式中提取出来
    expect(find.text('a'), findsWidgets);
  });

  testWidgets('宽屏布局：左侧历史常驻、右侧键盘', (tester) async {
    // 用窗口尺寸模拟横屏手机（900×400，宽高比 2.25）
    final win = tester.binding.window;
    win.physicalSizeTestValue = const Size(2700, 1200);
    win.devicePixelRatioTestValue = 3.0;
    addTearDown(() {
      win.physicalSizeTestValue = const Size(2400, 1800);
      win.devicePixelRatioTestValue = 3.0;
    });

    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.pumpAndSettle();

    // 宽屏分栏：左侧出现常驻历史栏，键盘仍可用
    expect(find.text('计算历史'), findsOneWidget);
    expect(find.byKey(const ValueKey('calcKey_7')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏仍为单列布局：无常驻历史栏', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.pumpAndSettle();
    // 默认 800×600，宽高比 1.33 < 1.5，按单列布局处理
    expect(find.text('计算历史'), findsNothing);
  });

  testWidgets('微积入口：生成 integral 表达式并求值', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toolCalculus')));
    await tester.pumpAndSettle();
    expect(find.text('微积分 / 方程求根'), findsOneWidget);

    // 默认：定积分 integral(x^2, 0, 1)
    expect(find.text('integral(x^2,0,1)'), findsOneWidget);
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    final ctrl = tester.widget<TextField>(find.byType(TextField).first).controller!;
    expect(ctrl.text, 'integral(x^2,0,1)');
    // ∫₀¹ x² dx = 1/3
    expect(find.textContaining('0.333333'), findsOneWidget);
  });

  testWidgets('微积入口：切换到导数可生成 diff 表达式', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toolCalculus')));
    await tester.pumpAndSettle();
    // 选择「导数」
    await tester.tap(find.text('定积分 ∫ f(x) dx'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导数 f′(x)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();

    final ctrl = tester.widget<TextField>(find.byType(TextField).first).controller!;
    expect(ctrl.text, startsWith('diff('));
  });
}

// —— v0.3.0：数据拟合页与图形读值 ——
void _dataTests() {
  testWidgets('数据页：底部第三个菜单，可拟合并显示 R²', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('数据'));
    await tester.pumpAndSettle();

    // 输入 y = 2x + 1 的数据
    await tester.enterText(find.byType(TextField).first, '1 3\n2 5\n3 7\n4 9');
    await tester.pumpAndSettle();

    // 线性拟合：方程与 R² 出现
    expect(find.textContaining('线性拟合'), findsOneWidget);
    expect(find.textContaining('R² = 1.000000'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets); // 散点图已绘制
  });

  testWidgets('数据页：拟合曲线可送到图形页', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('数据'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1 3\n2 5\n3 7\n4 9');
    await tester.pumpAndSettle();

    await tester.tap(find.text('送到图形页'));
    await tester.pumpAndSettle();

    // 已切到图形页（函数列表用 ListView.builder 懒加载，只断言页面切换成功）
    expect(find.text('图形计算器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图形页：读值标注开关与积分着色入口存在', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('annoToggle')), findsOneWidget);
    expect(find.byKey(const Key('integralShade')), findsOneWidget);

    // 打开积分着色对话框，输入区间后应用
    await tester.tap(find.byKey(const Key('integralShade')));
    await tester.pumpAndSettle();
    expect(find.text('积分面积着色'), findsOneWidget);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('图形页：开启标注后无渲染异常', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('annoToggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
