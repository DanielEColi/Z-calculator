import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_graph_calc/main.dart';

void main() {
  testWidgets('DEG/RAD 切换：按钮可见且点击后切换', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());

    // AppBar 中的 DEG 药丸：文字为白色，在蓝色 AppBar 上可见
    final degInAppBar = find.descendant(of: find.byType(AppBar), matching: find.text('DEG'));
    expect(degInAppBar, findsOneWidget);
    final degText = tester.widget<Text>(degInAppBar);
    expect(degText.style!.color, const Color(0xFFFFFFFF));

    // 点击切换到 RAD
    await tester.tap(degInAppBar);
    await tester.pump();
    expect(find.text('RAD'), findsNWidgets(2)); // AppBar 与计算器页两个药丸同步
    expect(find.text('DEG'), findsNothing);

    // 再点回 DEG
    final radInAppBar = find.descendant(of: find.byType(AppBar), matching: find.text('RAD'));
    await tester.tap(radInAppBar);
    await tester.pump();
    expect(find.text('DEG'), findsNWidgets(2));
    expect(find.text('RAD'), findsNothing);
  });

  testWidgets('键盘差异化尺寸：等号双宽、C 等功能键与数字键同格', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.pumpAndSettle();

    final wEq = tester.getSize(find.byKey(const ValueKey('calcKey_='))).width;
    final w7 = tester.getSize(find.byKey(const ValueKey('calcKey_7'))).width;
    final wC = tester.getSize(find.byKey(const ValueKey('calcKey_C'))).width;
    final wDiv = tester.getSize(find.byKey(const ValueKey('calcKey_÷'))).width;

    // 等号为双宽键（两个圆格 + 一个间距），明显大于数字键
    expect(wEq, closeTo(w7 * 2 + 10, 1.5));
    // 功能键与运算符为单圆格
    expect(wC, closeTo(w7, 0.5));
    expect(wDiv, closeTo(w7, 0.5));
    // 圆格为正方形
    final h7 = tester.getSize(find.byKey(const ValueKey('calcKey_7'))).height;
    expect(h7, closeTo(w7, 0.5));
  });

  testWidgets('科学键盘：切换到函数面板且按键齐全', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('科学键盘'));
    await tester.pumpAndSettle();
    expect(find.text('sin('), findsOneWidget);
    expect(find.text('ln('), findsOneWidget);
    expect(find.text('π'), findsOneWidget);
    expect(find.text('7'), findsNothing); // 数字键已切换掉
  });
}
