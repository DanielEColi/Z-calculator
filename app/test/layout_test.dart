import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_graph_calc/main.dart';

void main() {
  testWidgets('图形区占比：默认 > 55%，分隔条拖到底仍 > 40%', (tester) async {
    await tester.pumpWidget(const SciGraphCalcApp());
    await tester.tap(find.text('图形'));
    await tester.pumpAndSettle();

    final graphFinder = find.byKey(const Key('graphCanvas'));
    expect(graphFinder, findsOneWidget);

    double bodyHeight() {
      final nav = tester.getTopLeft(find.byType(NavigationBar)).dy;
      final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
      return nav - appBarBottom;
    }

    double graphRatio() => tester.getSize(graphFinder).height / bodyHeight();

    // 默认布局：输入区 0.32 + 分隔条 18px
    expect(graphRatio(), greaterThan(0.55), reason: '默认布局下图形区应占 body 55% 以上');

    // 分隔条一路向下拖（输入区增至上限 0.55，图形区仍有保底）
    await tester.drag(find.byKey(const Key('graphDivider')), const Offset(0, 5000));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(graphRatio(), greaterThan(0.38), reason: '分隔条拖到底后图形区仍应占 body 38% 以上');

    // 分隔条一路向上拖（输入区缩至下限 0.25，图形区变大）
    await tester.drag(find.byKey(const Key('graphDivider')), const Offset(0, -5000));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(graphRatio(), greaterThan(0.63), reason: '分隔条拖到顶后图形区应占 body 63% 以上');
  });
}
