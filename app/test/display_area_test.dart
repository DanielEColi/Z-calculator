import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:z_calculator/main.dart';

void main() {
  testWidgets('符号条：x² / e / π 使用公式字体（衬线斜体）', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    // e 与 π 分别用 serif + italic 渲染
    for (final label in ['e', 'π']) {
      final t = tester.widget<Text>(find.text(label).first);
      expect(t.style?.fontFamily, 'serif', reason: '$label 应使用衬线体');
      expect(t.style?.fontStyle, FontStyle.italic, reason: '$label 应为斜体');
    }

    // x² 为富文本：底数 x 斜体、指数 2 正体
    final richFinder = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == 'x²',
    );
    expect(richFinder, findsWidgets, reason: '符号条应有 x²');

    bool foundItalicX = false, foundNormalTwo = false;
    for (final rt in tester.widgetList<RichText>(richFinder)) {
      _walk(rt.text, (sp) {
        if (sp.text == 'x' && sp.style?.fontStyle == FontStyle.italic && sp.style?.fontFamily == 'serif') {
          foundItalicX = true;
        }
        if (sp.text == '²' && sp.style?.fontStyle == FontStyle.normal) {
          foundNormalTwo = true;
        }
      });
    }
    expect(foundItalicX, isTrue, reason: '底数 x 应为衬线斜体');
    expect(foundNormalTwo, isTrue, reason: '指数 2 应为正体');

    // 运算符保持正体无衬线，与变量区分
    final plus = tester.widget<Text>(find.text('+').first);
    expect(plus.style?.fontFamily, isNot('serif'));
    expect(plus.style?.fontStyle ?? FontStyle.normal, FontStyle.normal);
  });

  testWidgets('进制行：整数结果时稳定显示 HEX/OCT/BIN', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    // 输入 63-52 = 11（整数）
    for (final k in ['6', '3', '−', '5', '2']) {
      await tester.tap(find.byKey(ValueKey('calcKey_$k')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('11', skipOffstage: false), findsWidgets);
    // 进制行不再被上方内容挤掉
    // 标签带尾随空格（'HEX '），用 textContaining 匹配
    expect(find.textContaining('HEX'), findsOneWidget, reason: '整数结果应显示 HEX');
    expect(find.textContaining('OCT'), findsOneWidget);
    expect(find.textContaining('BIN'), findsOneWidget);
  });

  testWidgets('进制行：非整数结果不占位（不显示空行）', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    // 10/3 = 3.333... 非整数
    for (final k in ['1', '0', '÷', '3']) {
      await tester.tap(find.byKey(ValueKey('calcKey_$k')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('HEX'), findsNothing, reason: '非整数不该有进制行');
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果区：有结果才占位，空结果不留空行', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());

    double boxH() => tester.getSize(find.byKey(const Key('calcResultBox'))).height;

    // 初始：无结果 → 结果区收起
    expect(boxH(), lessThan(10), reason: '无结果时不应占 44px 空行');

    // 输入完整表达式 2+3*4 → 有结果，结果区展开
    for (final k in ['2', '+', '3', '×', '4']) {
      await tester.tap(find.byKey(ValueKey('calcKey_$k')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('14', skipOffstage: false), findsOneWidget);
    expect(boxH(), greaterThan(30), reason: '有结果时结果区应展开');

    // 输入不完整表达式（末位运算符）→ 结果消失，结果区收起，不留下空行
    await tester.tap(find.byKey(const ValueKey('calcKey_C')));
    await tester.pump();
    for (final k in ['9', '5', '×']) {
      await tester.tap(find.byKey(ValueKey('calcKey_$k')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(boxH(), lessThan(10), reason: '表达式不完整时结果区应收起');
    expect(tester.takeException(), isNull);
  });
}

/// 递归遍历 InlineSpan，回调每个 TextSpan
void _walk(InlineSpan span, void Function(TextSpan) visit) {
  if (span is TextSpan) {
    visit(span);
    for (final c in span.children ?? const <InlineSpan>[]) {
      _walk(c, visit);
    }
  }
}
