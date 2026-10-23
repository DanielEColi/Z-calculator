import 'package:flutter_test/flutter_test.dart';
import 'package:sci_graph_calc/main.dart';

void main() {
  test('表达式引擎：隐式乘法 / DEG / 常数 / 阶乘 / 错误', () {
    expect(evaluate('2x', 3, {}, AngleMode.rad, 0), closeTo(6, 1e-12));
    expect(evaluate('3sin x', 30, {}, AngleMode.deg, 0), closeTo(1.5, 1e-12));
    expect(evaluate('(x+1)(x-1)', 2, {}, AngleMode.rad, 0), closeTo(3, 1e-12));
    expect(evaluate('sin(30)', 0, {}, AngleMode.deg, 0), closeTo(0.5, 1e-12));
    expect(evaluate('3pi', 0, {}, AngleMode.rad, 0), closeTo(3 * 3.141592653589793, 1e-9));
    expect(evaluate('a*x^2', 2, {'a': 1.5}, AngleMode.rad, 0), closeTo(6, 1e-12));
    expect(evaluate('2^-1', 0, {}, AngleMode.rad, 0), closeTo(0.5, 1e-12));
    expect(evaluate('5!', 0, {}, AngleMode.rad, 0), closeTo(120, 1e-12));
    expect(evaluate('ans*2', 0, {}, AngleMode.rad, 21), closeTo(42, 1e-12));
    expect(evaluate('1/x', 0, {}, AngleMode.rad, 0).isInfinite, isTrue);
    expect(evaluate('sqrt(x)', -1, {}, AngleMode.rad, 0).isNaN, isTrue);

    // 参数收集
    expect(collectParams('a*x^2 + b'), {'a', 'b'});
    expect(collectParams('sin(x) + pi'), <String>{});

    // 错误必须抛出 ExprError 而不是崩溃
    expect(() => evaluate('2+', 0, {}, AngleMode.rad, 0), throwsA(isA<ExprError>()));
    expect(() => evaluate('(x+1', 0, {}, AngleMode.rad, 0), throwsA(isA<ExprError>()));
    expect(evaluate('ln(-1)', 0, {}, AngleMode.rad, 0).isNaN, isTrue);
  });
}
