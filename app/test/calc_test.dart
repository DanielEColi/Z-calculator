import 'package:flutter_test/flutter_test.dart';
import 'package:sci_graph_calc/main.dart';

void main() {
  test('数值积分', () {
    expect(evaluate('integral(x^2,0,1)', 0, {}, AngleMode.rad, 0), closeTo(1/3, 1e-9));
    expect(evaluate('integral(sin(x),0,pi)', 0, {}, AngleMode.rad, 0), closeTo(2, 1e-8));
    expect(evaluate('integral(1,0,5)', 0, {}, AngleMode.rad, 0), closeTo(5, 1e-9));
    expect(evaluate('integral(exp(x),0,1)', 0, {}, AngleMode.rad, 0), closeTo(2.718281828-1, 1e-8));
    // 反向积分为负
    expect(evaluate('integral(x,1,0)', 0, {}, AngleMode.rad, 0), closeTo(-0.5, 1e-9));
  });

  test('数值导数', () {
    expect(evaluate('diff(x^2,3)', 0, {}, AngleMode.rad, 0), closeTo(6, 1e-5));
    expect(evaluate('diff(sin(x),0)', 0, {}, AngleMode.rad, 0), closeTo(1, 1e-5));
    expect(evaluate('diff(ln(x),1)', 0, {}, AngleMode.rad, 0), closeTo(1, 1e-5));
  });

  test('通用方程求根', () {
    expect(evaluate('solve(x^2-2,0,2)', 0, {}, AngleMode.rad, 0), closeTo(1.41421356, 1e-6));
    expect(evaluate('solve(cos(x),0,3)', 0, {}, AngleMode.rad, 0), closeTo(1.5707963, 1e-6));
    expect(evaluate('solve(x^3-x-2,1,2)', 0, {}, AngleMode.rad, 0), closeTo(1.5213797, 1e-6));
  });

  test('高阶函数可嵌套 / 参与表达式运算', () {
    expect(evaluate('2*integral(x,0,3)', 0, {}, AngleMode.rad, 0), closeTo(9, 1e-8));
    expect(evaluate('integral(1,0,solve(x-4,0,10))', 0, {}, AngleMode.rad, 0), closeTo(4, 1e-6));
  });

  test('高阶函数名不被拆成字母参数', () {
    expect(collectParams('integral(a*x,0,1)'), {'a'});
    expect(collectParams('diff(a*x^2,1)'), {'a'});
  });
}
