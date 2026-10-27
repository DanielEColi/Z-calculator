import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_graph_calc/main.dart';

void main() {
  test('数据解析：空格 / 逗号 / 中文逗号 / 制表符 / 空行与注释', () {
    final pts = parseData('1 2\n2,4\n3，6\n4\t8\n\n# 注释行\n5 10');
    expect(pts.length, 5);
    expect(pts.map((p) => p.x).toList(), [1, 2, 3, 4, 5]);
    expect(pts.map((p) => p.y).toList(), [2, 4, 6, 8, 10]);
  });

  test('线性拟合：y = 2x + 1 可精确还原', () {
    final pts = [for (int i = 1; i <= 6; i++) Pt(i.toDouble(), 2.0 * i + 1)];
    final r = fitData(pts, 'linear')!;
    expect(r.name, '线性');
    expect(r.f(3), closeTo(7, 1e-9));
    expect(r.r2, closeTo(1.0, 1e-12));
  });

  test('二次拟合：还原抛物线系数', () {
    final pts = <Pt>[];
    for (int i = -3; i <= 3; i++) {
      final x = i.toDouble();
      pts.add(Pt(x, x * x - 2 * x + 3));
    }
    final r = fitData(pts, 'poly2')!;
    expect(r.f(0), closeTo(3, 1e-8));
    expect(r.f(2), closeTo(3, 1e-8));
    expect(r.r2, closeTo(1.0, 1e-10));
  });

  test('指数 / 对数 / 幂拟合：变换后可还原', () {
    final exp = [for (int i = 0; i <= 5; i++) Pt(i.toDouble(), 2.0 * math.exp(0.5 * i))];
    final re = fitData(exp, 'exp')!;
    expect(re.f(2), closeTo(2 * math.exp(1), 1e-6));
    expect(re.r2, closeTo(1.0, 1e-9));

    final log = [for (int i = 1; i <= 6; i++) Pt(i.toDouble(), 3 + 2 * math.log(i))];
    final rl = fitData(log, 'log')!;
    expect(rl.f(math.e), closeTo(5, 1e-6));
    expect(rl.r2, closeTo(1.0, 1e-9));

    final pow = [for (int i = 1; i <= 6; i++) Pt(i.toDouble(), 2.0 * math.pow(i, 1.5).toDouble())];
    final rp = fitData(pow, 'power')!;
    expect(rp.f(4), closeTo(16, 1e-6));
    expect(rp.r2, closeTo(1.0, 1e-9));
  });

  test('拟合前置校验：模型与数据不匹配时返回 null', () {
    final withNeg = [for (int i = -2; i <= 2; i++) Pt(i.toDouble(), i.toDouble() + 3)];
    expect(fitData(withNeg, 'log'), isNull, reason: 'x<=0 不能做对数拟合');
    final withNegY = [for (int i = 1; i <= 4; i++) Pt(i.toDouble(), -1.0 * i)];
    expect(fitData(withNegY, 'exp'), isNull, reason: 'y<=0 不能做指数拟合');
    expect(fitData([Pt(1, 1), Pt(2, 2)], 'poly3'), isNull, reason: '三点不足四次拟合');
  });

  test('R² 与皮尔逊 r：完全线性时都是 1', () {
    final pts = [for (int i = 1; i <= 5; i++) Pt(i.toDouble(), 3.0 * i)];
    expect(pearsonR(pts), closeTo(1.0, 1e-12));
    expect(rSquared(pts, (x) => 3 * x), closeTo(1.0, 1e-12));
  });

  test('线性方程组求解', () {
    final c = solveLinear([
      [2.0, 1.0],
      [1.0, 3.0],
    ], [3.0, 5.0]);
    // 2x + y = 3, x + 3y = 5 → x = 0.8, y = 1.4
    expect(c[0], closeTo(0.8, 1e-9));
    expect(c[1], closeTo(1.4, 1e-9));
  });
}
