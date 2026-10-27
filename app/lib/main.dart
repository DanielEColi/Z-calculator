import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const SciGraphCalcApp());

class SciGraphCalcApp extends StatefulWidget {
  const SciGraphCalcApp({super.key});
  @override
  State<SciGraphCalcApp> createState() => _SciGraphCalcAppState();
}

class _SciGraphCalcAppState extends State<SciGraphCalcApp> {
  bool dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Z-Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF), brightness: Brightness.light),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7FA6FF), brightness: Brightness.dark),
      ),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: HomePage(
        dark: dark,
        onToggleDark: () => setState(() => dark = !dark),
      ),
    );
  }
}

// ============================ 表达式引擎 ============================

enum AngleMode { deg, rad }

class ExprError implements Exception {
  final String message;
  ExprError(this.message);
}

abstract class _Node {
  double eval(double x, Map<String, double> p, AngleMode am);
}

class _Num implements _Node {
  final double v;
  _Num(this.v);
  @override
  double eval(double x, Map<String, double> p, AngleMode am) => v;
}

class _Var implements _Node {
  final String name;
  _Var(this.name);
  @override
  double eval(double x, Map<String, double> p, AngleMode am) {
    if (name == 'x') return x;
    final v = p[name];
    if (v == null) throw ExprError('未知变量 "$name"');
    return v;
  }
}

class _Bin implements _Node {
  final String op;
  final _Node a, b;
  _Bin(this.op, this.a, this.b);
  @override
  double eval(double x, Map<String, double> p, AngleMode am) {
    final l = a.eval(x, p, am), r = b.eval(x, p, am);
    switch (op) {
      case '+': return l + r;
      case '-': return l - r;
      case '*': return l * r;
      case '/': return l / r;
      case '^':
        if (l < 0) {
          // 负底数：指数为整数时按奇偶定符号；允许奇数根（如 (-8)^(1/3)）；否则未定义
          if (r == r.roundToDouble()) {
            final t = math.pow(l.abs(), r).toDouble();
            return r.round().isOdd ? -t : t;
          }
          final inv = 1 / r;
          if (inv == inv.roundToDouble() && inv.round().isOdd) {
            return -math.pow(l.abs(), r).toDouble();
          }
          return double.nan;
        }
        return math.pow(l, r).toDouble();
    }
    throw ExprError('未知运算符 "$op"');
  }
}

class _Neg implements _Node {
  final _Node a;
  _Neg(this.a);
  @override
  double eval(double x, Map<String, double> p, AngleMode am) => -a.eval(x, p, am);
}

class _Fn implements _Node {
  final String name;
  final _Node a;
  _Fn(this.name, this.a);
  @override
  double eval(double x, Map<String, double> p, AngleMode am) {
    final v = a.eval(x, p, am);
    final d2r = math.pi / 180, r2d = 180 / math.pi;
    switch (name) {
      case 'sin': return am == AngleMode.deg ? math.sin(v * d2r) : math.sin(v);
      case 'cos': return am == AngleMode.deg ? math.cos(v * d2r) : math.cos(v);
      case 'tan': return am == AngleMode.deg ? math.tan(v * d2r) : math.tan(v);
      case 'asin': return am == AngleMode.deg ? math.asin(v) * r2d : math.asin(v);
      case 'acos': return am == AngleMode.deg ? math.acos(v) * r2d : math.acos(v);
      case 'atan': return am == AngleMode.deg ? math.atan(v) * r2d : math.atan(v);
      case 'ln': return math.log(v);
      case 'log': return math.log(v) / math.ln10;
      case 'log2': return math.log(v) / math.ln2;
      case 'sqrt': return math.sqrt(v);
      case 'abs': return v.abs();
      case 'exp': return math.exp(v);
    }
    throw ExprError('未知函数 "$name"');
  }
}

class _Fact implements _Node {
  final _Node a;
  _Fact(this.a);
  @override
  double eval(double x, Map<String, double> p, AngleMode am) {
    final v = a.eval(x, p, am);
    if (v < 0 || v != v.roundToDouble() || v > 170) return double.nan;
    double r = 1;
    for (int i = 2; i <= v.round(); i++) {
      r *= i;
    }
    return r;
  }
}

/// 表达式包裹器：把子表达式当作「函数体」传给高阶函数，
/// 自身不求值（返回 NaN），由父节点（[_HOF]）在不同取样点反复求值。
class _Lam implements _Node {
  final _Node body;
  _Lam(this.body);
  @override
  double eval(double x, Map<String, double> p, AngleMode am) => double.nan;
}

/// 高阶函数调用：第一个参数是 [_Lam]，其余为普通数值参数
class _HOF implements _Node {
  final String name;
  final _Lam lam;
  final List<_Node> args;
  _HOF(this.name, this.lam, this.args);

  @override
  double eval(double x, Map<String, double> p, AngleMode am) {
    final v = args.map((a) => a.eval(x, p, am)).toList();
    for (final e in v) {
      if (!e.isFinite) throw ExprError('$name 的参数必须是有限数值');
    }
    // lambda 的自变量固定为 x
    double f(double xv) => lam.body.eval(xv, p, am);
    switch (name) {
      case 'integral':
        if (v.length != 2) throw ExprError('integral(表达式, 下限, 上限) 需要两个界限');
        return integrate(f, v[0], v[1]);
      case 'diff':
        if (v.length == 1) return derivative(f, v[0]);
        if (v.length == 2) {
          // diff(表达式, 点, 精度)
          return derivativeAt(f, v[0], v[1]);
        }
        throw ExprError('diff(表达式, 点) 需要一个求值点');
      case 'solve':
        if (v.length != 2) throw ExprError('solve(表达式, 下限, 上限) 需要搜索区间');
        return solveRoot(f, v[0], v[1]);
    }
    throw ExprError('未知的高阶函数 "$name"');
  }
}

const _functions = {
  'sin': 1, 'cos': 1, 'tan': 1, 'asin': 1, 'acos': 1, 'atan': 1,
  'ln': 1, 'log': 1, 'log2': 1, 'sqrt': 1, 'abs': 1, 'exp': 1,
};

/// 高阶函数：第一个参数是「表达式（AST）」而非数值，因此单独处理。
/// integral(f, a, b) 定积分；diff(f, at) 在点 at 处的导数；solve(f, a, b) 在 [a,b] 内求零点
const _hofFns = {'integral': 0, 'diff': 0, 'solve': 0};

class _Tok {
  final String type; // num id op lp rp fact comma
  final String text;
  _Tok(this.type, this.text);
  @override
  String toString() => '$type($text)';
}

/// 词法 + 隐式乘法 + "sin x" → "sin(x)"
List<_Tok> _tokenize(String src) {
  final raw = <_Tok>[];
  int i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == ' ') { i++; continue; }
    if (_isDigit(c) || (c == '.' && i + 1 < src.length && _isDigit(src[i + 1]))) {
      int j = i;
      while (j < src.length && (_isDigit(src[j]) || src[j] == '.')) { j++; }
      raw.add(_Tok('num', src.substring(i, j)));
      i = j;
    } else if (_isLetter(c)) {
      int j = i;
      while (j < src.length && _isLetter(src[j])) { j++; }
      // 保留原始大小写：变量名区分大小写（A 与 a 是不同参数）
      raw.add(_Tok('id', src.substring(i, j)));
      i = j;
    } else if ('+-*/^'.contains(c)) {
      raw.add(_Tok('op', c));
      i++;
    } else if (c == ',') {
      raw.add(_Tok('comma', ','));
      i++;
    } else if (c == '(' || c == '[') {
      raw.add(_Tok('lp', '('));
      i++;
    } else if (c == ')' || c == ']') {
      raw.add(_Tok('rp', ')'));
      i++;
    } else if (c == '!') {
      raw.add(_Tok('fact', '!'));
      i++;
    } else {
      throw ExprError('无法识别的字符 "$c"');
    }
  }
  // 多字母标识符拆分：函数名 / pi / e / 单字母变量
  // 注意：函数名与常量大小写不敏感（sin/SIN 均可），但变量保留原始大小写（A 与 a 不同）
  final out = <_Tok>[];
  for (final t in raw) {
    if (t.type == 'id') {
      final s = t.text;
      final low = s.toLowerCase();
      if (low.length == 1 && (low == 'x' || low == 'y')) {
        // 自变量 x / 因变量 y：大小写统一
        out.add(_Tok('id', low));
      } else if (_functions.containsKey(low) || _hofFns.containsKey(low) ||
          low == 'pi' || low == 'ans') {
        out.add(_Tok('id', low));
      } else if (s.length == 1) {
        // 单字母变量：保留原始大小写（小写 e 仍为自然常数；X/Y 归一为 x/y）
        final ch = s;
        if (ch == 'X' || ch == 'Y') {
          out.add(_Tok('id', ch.toLowerCase()));
        } else {
          out.add(_Tok('id', ch));
        }
      } else {
        int k = 0;
        while (k < s.length) {
          int best = 0;
          final rest = s.substring(k).toLowerCase();
          // 高阶函数名优先于普通函数名匹配（integral / diff / solve 不能被拆成字母）
          for (final f in _hofFns.keys) {
            if (rest.startsWith(f)) {
              best = f.length;
              out.add(_Tok('id', f));
              break;
            }
          }
          if (best == 0) {
            for (final f in _functions.keys) {
              if (rest.startsWith(f)) {
                best = f.length;
                out.add(_Tok('id', f));
                break;
              }
            }
          }
          if (best == 0) {
            if (rest.startsWith('pi')) {
              out.add(_Tok('id', 'pi'));
              best = 2;
            } else {
              // 变量字符：保留原始大小写，但 x/y 大小写统一
              final ch = s[k];
              out.add(_Tok('id', (ch == 'X' || ch == 'Y') ? ch.toLowerCase() : ch));
              best = 1;
            }
          }
          k += best;
        }
      }
    } else {
      out.add(t);
    }
  }
  // 隐式乘法：2x → 2*x、(x+1)(x-1) → 相乘、3pi → 3*pi
  final mul = <_Tok>[];
  for (final t in out) {
    if (mul.isNotEmpty) {
      final prev = mul.last;
      final prevVal = prev.type == 'num' || prev.type == 'rp' ||
          (prev.type == 'id' &&
              !_functions.containsKey(prev.text) &&
              !_hofFns.containsKey(prev.text)); // 函数名后不加 *
      final curStarts = t.type == 'num' || t.type == 'id' || t.type == 'lp';
      if (prevVal && curStarts) mul.add(_Tok('op', '*'));
    }
    mul.add(t);
  }
  // 函数后无括号：sin x → sin(x)、sin 2x → sin(2x)
  final wrapped = <_Tok>[];
  for (int k = 0; k < mul.length; k++) {
    final t = mul[k];
    wrapped.add(t);
    if (t.type == 'id' && _functions.containsKey(t.text)) {
      if (k + 1 >= mul.length || mul[k + 1].type != 'lp') {
        int depth = 0, end = mul.length;
        for (int m = k + 1; m < mul.length; m++) {
          final u = mul[m];
          if (u.type == 'lp') depth++;
          if (u.type == 'rp') {
            if (depth == 0) { end = m; break; }
            depth--;
          }
          if (depth == 0 && u.type == 'op' && (u.text == '+' || u.text == '-' || u.text == '*' || u.text == '/')) {
            end = m;
            break;
          }
        }
        wrapped.add(_Tok('lp', '('));
        for (int m = k + 1; m < end; m++) {
          wrapped.add(mul[m]);
        }
        wrapped.add(_Tok('rp', ')'));
        k = end - 1;
      }
    }
  }
  return wrapped;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
bool _isLetter(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 97 && u <= 122) || (u >= 65 && u <= 90);
}

class Parser {
  final List<_Tok> toks;
  int pos = 0;
  Parser(String src) : toks = _tokenize(src);

  _Tok get peek => pos < toks.length ? toks[pos] : _Tok('eof', '');
  _Tok next() => pos < toks.length ? toks[pos++] : _Tok('eof', '');

  _Node parse() {
    final n = _expr();
    if (peek.type != 'eof') throw ExprError('位置 ${pos + 1} 处有多余的 "${peek.text}"');
    return n;
  }

  _Node _expr() {
    var n = _term();
    while (peek.type == 'op' && (peek.text == '+' || peek.text == '-')) {
      final op = next().text;
      n = _Bin(op, n, _term());
    }
    return n;
  }

  _Node _term() {
    var n = _unary();
    while (peek.type == 'op' && (peek.text == '*' || peek.text == '/')) {
      final op = next().text;
      n = _Bin(op, n, _unary());
    }
    return n;
  }

  _Node _unary() {
    if (peek.type == 'op' && peek.text == '-') {
      next();
      return _Neg(_unary());
    }
    if (peek.type == 'op' && peek.text == '+') {
      next();
      return _unary();
    }
    return _power();
  }

  _Node _power() {
    final base = _primary();
    if (peek.type == 'op' && peek.text == '^') {
      next();
      return _Bin('^', base, _unary());
    }
    return base;
  }

  _Node _primary() {
    final t = next();
    if (t.type == 'num') {
      final v = double.tryParse(t.text);
      if (v == null) throw ExprError('非法数字 "${t.text}"');
      return _postfix(_Num(v));
    }
    if (t.type == 'lp') {
      final n = _expr();
      if (next().type != 'rp') throw ExprError('括号未闭合');
      return _postfix(n);
    }
    if (t.type == 'id') {
      if (_hofFns.containsKey(t.text)) {
        if (peek.type != 'lp') throw ExprError('${t.text} 后缺少 (');
        next();
        final body = _expr(); // 第一个参数：表达式本身（不求值）
        final args = <_Node>[];
        while (peek.type == 'comma') {
          next();
          args.add(_expr());
        }
        if (next().type != 'rp') throw ExprError('${t.text}( 括号未闭合');
        return _postfix(_HOF(t.text, _Lam(body), args));
      }
      if (_functions.containsKey(t.text)) {
        if (peek.type != 'lp') throw ExprError('${t.text} 后缺少 (');
        next();
        final arg = _expr();
        if (next().type != 'rp') throw ExprError('${t.text}( 括号未闭合');
        return _postfix(_Fn(t.text, arg));
      }
      if (t.text == 'pi') return _postfix(_Num(math.pi));
      if (t.text == 'e') return _postfix(_Num(math.e));
      if (t.text == 'ans') return _postfix(_Var('ans'));
      if (t.text.length == 1) return _postfix(_Var(t.text));
      throw ExprError('无法识别的名称 "${t.text}"');
    }
    if (t.type == 'eof') throw ExprError('表达式不完整');
    throw ExprError('意外的 "${t.text}"');
  }

  _Node _postfix(_Node n) {
    while (peek.type == 'fact') {
      next();
      n = _Fact(n);
    }
    return n;
  }
}

/// 定积分（自适应 Simpson）：∫ f(x) dx over [a, b]
double integrate(double Function(double) f, double a, double b) {
  if (!(a.isFinite && b.isFinite)) throw ExprError('积分上下限必须是有限数值');
  if (a == b) return 0;
  if (b < a) return -integrate(f, b, a);
  final fa = f(a);
  final fb = f(b);
  // 端点不可求值（如 1/(x-1) 落在奇点上）：从内侧收缩
  if (!fa.isFinite || !fb.isFinite) {
    final eps = (b - a) * 1e-9;
    return integrate(f, a + eps, b - eps);
  }
  final fc = f((a + b) / 2);
  if (!fc.isFinite) {
    // 区间内存在奇点：劈成两半分别处理
    final c = (a + b) / 2;
    return integrate(f, a, c) + integrate(f, c, b);
  }
  final whole = (b - a) / 6 * (fa + 4 * fc + fb);
  return _adapt(f, a, b, 1e-10, whole, fa, fc, fb, 0);
}

double _adapt(double Function(double) f, double a, double b, double eps, double whole,
    double fa, double fc, double fb, int depth) {
  final c = (a + b) / 2;
  final d = (a + c) / 2;
  final e = (c + b) / 2;
  final fd = f(d);
  final fe = f(e);
  // 子段采样到非有限值（极点）：继续二分；过深则放弃该微小段的贡献
  if (!fd.isFinite || !fe.isFinite) {
    if (depth >= 50) return 0;
    final left = _adapt(f, a, c, eps / 2, (c - a) / 6 * (fa + 4 * f((a + c) / 2) + fc), fa,
        f((a + c) / 2), fc, depth + 1);
    final right = _adapt(f, c, b, eps / 2, (b - c) / 6 * (fc + 4 * f((c + b) / 2) + fb), fc,
        f((c + b) / 2), fb, depth + 1);
    return left + right;
  }
  final left = (c - a) / 6 * (fa + 4 * fd + fc);
  final right = (b - c) / 6 * (fc + 4 * fe + fb);
  final delta = left + right - whole;
  if (depth >= 30 || delta.abs() <= 15 * eps) return left + right + delta / 15;
  return _adapt(f, a, c, eps / 2, left, fa, fd, fc, depth + 1) +
      _adapt(f, c, b, eps / 2, right, fc, fe, fb, depth + 1);
}

/// 数值导数：默认中心差分；单点不可求值时退化为单侧差分
double derivative(double Function(double) f, double x0) => derivativeAt(f, x0, null);

double derivativeAt(double Function(double) f, double x0, double? h0) {
  final h = h0 ?? math.max(1e-6, x0.abs() * 1e-6);
  if (h <= 0) throw ExprError('导数步长必须为正');
  final fp = f(x0 + h);
  final fm = f(x0 - h);
  if (fp.isFinite && fm.isFinite) return (fp - fm) / (2 * h);
  final f0 = f(x0);
  if (fp.isFinite && f0.isFinite) return (fp - f0) / h;
  if (fm.isFinite && f0.isFinite) return (f0 - fm) / h;
  throw ExprError('在 x = $x0 处无法求导');
}

/// 在 [a, b] 内求零点：先扫描定位变号区间，再二分收敛。
/// 找不到时抛 [ExprError]，让调用方能明确提示「区间内无根」。
double solveRoot(double Function(double) f, double a, double b) {
  if (!(a.isFinite && b.isFinite)) throw ExprError('求根区间必须是有限数值');
  double lo = a, hi = b;
  if (lo > hi) {
    final t = lo;
    lo = hi;
    hi = t;
  }
  const n = 512;
  var prevX = lo;
  var prevY = f(lo);
  if (prevY.abs() < 1e-12) return lo;
  for (int i = 1; i <= n; i++) {
    final x = lo + (hi - lo) * i / n;
    final y = f(x);
    if (!y.isFinite) {
      prevX = x;
      prevY = y;
      continue;
    }
    if (y.abs() < 1e-12) return x;
    if (prevY.isFinite && prevY * y <= 0) {
      var l = prevX, r = x, fl = prevY;
      for (int k = 0; k < 100; k++) {
        final m = (l + r) / 2;
        final fm = f(m);
        if (!fm.isFinite) break;
        if (fl * fm <= 0) {
          r = m;
        } else {
          l = m;
          fl = fm;
        }
        if ((r - l).abs() < 1e-14) break;
      }
      return (l + r) / 2;
    }
    prevX = x;
    prevY = y;
  }
  throw ExprError('在 [$lo, $hi] 内未找到零点，可换更宽的区间');
}

// ============================ 数据拟合引擎 ============================

/// 一个数据点
class Pt {
  final double x, y;
  Pt(this.x, this.y);
}

/// 拟合结果：可显示的方程文本、可直接送到图形页的表达式、预测函数、R²
class FitResult {
  final String kind; // 'linear' | 'poly2' | 'poly3' | 'exp' | 'log' | 'power'
  final String name; // 中文名
  final String equation; // 可读方程，如 y = 1.23 + 0.45·x
  final String expr; // 图形页可解析的表达式
  final double Function(double) f;
  final double r2;
  final int n;
  FitResult(this.kind, this.name, this.equation, this.expr, this.f, this.r2, this.n);
}

/// 解析文本数据：每行（或逗号分隔）取前两个数字作为 x, y
List<Pt> parseData(String text) {
  final out = <Pt>[];
  for (final raw in text.split(RegExp(r'[\n;\r]+'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    // 支持 "x,y" / "x y" / "x<TAB>y" / "x，y"（中文逗号）
    final parts = line.split(RegExp(r'[\s,\t，]+'));
    if (parts.length < 2) continue;
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    if (x == null || y == null) continue;
    if (!x.isFinite || !y.isFinite) continue;
    out.add(Pt(x, y));
  }
  return out;
}

/// 高斯消元求解线性方程组（含部分选主元）；奇异时返回 NaN 列表
List<double> solveLinear(List<List<double>> a, List<double> b) {
  final n = b.length;
  final m = List<List<double>>.generate(n, (i) => <double>[...a[i], b[i]]);
  for (int col = 0; col < n; col++) {
    var piv = col;
    for (int r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[piv][col].abs()) piv = r;
    }
    if (m[piv][col].abs() < 1e-14) return List<double>.filled(n, double.nan);
    if (piv != col) {
      final t = m[col];
      m[col] = m[piv];
      m[piv] = t;
    }
    for (int r = 0; r < n; r++) {
      if (r == col) continue;
      final f = m[r][col] / m[col][col];
      if (f == 0) continue;
      for (int c = col; c <= n; c++) {
        m[r][c] -= f * m[col][c];
      }
    }
  }
  return List<double>.generate(n, (i) => m[i][n] / m[i][i]);
}

/// 多项式最小二乘拟合（degree 阶），返回系数 [c0, c1, ...]
List<double> polyFit(List<Pt> pts, int degree) {
  final n = degree + 1;
  if (pts.length < n) return List<double>.filled(n, double.nan);
  final a = List<List<double>>.generate(n, (_) => List<double>.filled(n, 0.0));
  final b = List<double>.filled(n, 0.0);
  for (final p in pts) {
    final pw = List<double>.generate(2 * degree + 1, (i) => math.pow(p.x, i).toDouble());
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        a[i][j] += pw[i + j];
      }
      b[i] += pw[i] * p.y;
    }
  }
  return solveLinear(a, b);
}

/// 决定系数 R² = 1 − SSres/SStot
double rSquared(List<Pt> pts, double Function(double) f) {
  if (pts.isEmpty) return double.nan;
  var mean = 0.0;
  for (final p in pts) {
    mean += p.y;
  }
  mean /= pts.length;
  var ssRes = 0.0, ssTot = 0.0;
  for (final p in pts) {
    final yv = f(p.x);
    if (!yv.isFinite) return double.nan;
    ssRes += (p.y - yv) * (p.y - yv);
    ssTot += (p.y - mean) * (p.y - mean);
  }
  if (ssTot == 0) return ssRes == 0 ? 1.0 : double.nan;
  return 1 - ssRes / ssTot;
}

/// 皮尔逊相关系数 r
double pearsonR(List<Pt> pts) {
  final n = pts.length;
  if (n < 2) return double.nan;
  var sx = 0.0, sy = 0.0;
  for (final p in pts) {
    sx += p.x;
    sy += p.y;
  }
  final mx = sx / n, my = sy / n;
  var num = 0.0, dx = 0.0, dy = 0.0;
  for (final p in pts) {
    final a = p.x - mx, b = p.y - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  if (dx == 0 || dy == 0) return double.nan;
  return num / math.sqrt(dx * dy);
}

/// 系数格式化：便于拼出可粘贴到表达式输入框的方程
String fmtCoef(double v) {
  if (v == 0) return '0';
  final a = v.abs();
  if (a >= 1e6 || a < 1e-4) return v.toStringAsExponential(4);
  var s = v.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

/// 拟合入口：按 kind 选择模型，自动做必要的变量变换
FitResult? fitData(List<Pt> pts, String kind) {
  if (pts.length < 2) return null;
  switch (kind) {
    case 'linear':
    case 'poly2':
    case 'poly3':
      final deg = kind == 'linear' ? 1 : (kind == 'poly2' ? 2 : 3);
      if (pts.length <= deg) return null;
      final c = polyFit(pts, deg);
      if (c.any((e) => !e.isFinite)) return null;
      double f(double x) {
        var r = 0.0, xp = 1.0;
        for (final e in c) {
          r += e * xp;
          xp *= x;
        }
        return r;
      }
      final terms = <String>[];
      for (int i = c.length - 1; i >= 0; i--) {
        if (c[i] == 0) continue;
        final mono = i == 0 ? fmtCoef(c[i]) : (i == 1 ? '${fmtCoef(c[i])}*x' : '${fmtCoef(c[i])}*x^$i');
        terms.add(mono);
      }
      final expr = terms.isEmpty ? '0' : terms.join('+');
      final name = deg == 1 ? '线性' : (deg == 2 ? '二次多项式' : '三次多项式');
      return FitResult(kind, name, 'y = $expr', expr, f, rSquared(pts, f), pts.length);
    case 'exp':
      if (pts.any((p) => p.y <= 0)) return null;
      final t = [for (final p in pts) Pt(p.x, math.log(p.y))];
      final c = polyFit(t, 1);
      if (c.any((e) => !e.isFinite)) return null;
      final A = math.exp(c[0]), B = c[1];
      double f(double x) => A * math.exp(B * x);
      return FitResult(
          kind, '指数', 'y = ${fmtCoef(A)}·e^(${fmtCoef(B)}·x)', '${fmtCoef(A)}*exp(${fmtCoef(B)}*x)',
          f, rSquared(pts, f), pts.length);
    case 'log':
      if (pts.any((p) => p.x <= 0)) return null;
      final t = [for (final p in pts) Pt(math.log(p.x), p.y)];
      final c = polyFit(t, 1);
      if (c.any((e) => !e.isFinite)) return null;
      double f(double x) => c[0] + c[1] * math.log(x);
      return FitResult(
          kind, '对数', 'y = ${fmtCoef(c[0])} + ${fmtCoef(c[1])}·ln(x)',
          '${fmtCoef(c[0])}+${fmtCoef(c[1])}*ln(x)', f, rSquared(pts, f), pts.length);
    case 'power':
      if (pts.any((p) => p.x <= 0 || p.y <= 0)) return null;
      final t = [for (final p in pts) Pt(math.log(p.x), math.log(p.y))];
      final c = polyFit(t, 1);
      if (c.any((e) => !e.isFinite)) return null;
      final A = math.exp(c[0]), B = c[1];
      double f(double x) => A * math.pow(x, B);
      return FitResult(
          kind, '幂', 'y = ${fmtCoef(A)}·x^${fmtCoef(B)}', '${fmtCoef(A)}*x^${fmtCoef(B)}',
          f, rSquared(pts, f), pts.length);
  }
  return null;
}

/// 散点图 + 拟合曲线绘制器（数据页用）
class _ScatterPainter extends CustomPainter {
  final List<Pt> pts;
  final FitResult? fit;
  final Color gridColor, axisColor, labelColor;
  _ScatterPainter(this.pts, this.fit,
      {required this.gridColor, required this.axisColor, required this.labelColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty || size.width <= 0 || size.height <= 0) return;
    final tp = TextPainter()..textDirection = TextDirection.ltr;
    final pad = 26.0;
    var xmin = pts.first.x, xmax = pts.first.x, ymin = pts.first.y, ymax = pts.first.y;
    for (final p in pts) {
      if (p.x < xmin) xmin = p.x;
      if (p.x > xmax) xmax = p.x;
      if (p.y < ymin) ymin = p.y;
      if (p.y > ymax) ymax = p.y;
    }
    // 把拟合曲线的取值范围也算进去，避免曲线被裁掉
    final f = fit?.f;
    if (f != null) {
      const m = 80;
      for (int i = 0; i <= m; i++) {
        final x = xmin + (xmax - xmin) * i / m;
        final y = f(x);
        if (!y.isFinite) continue;
        if (y < ymin) ymin = y;
        if (y > ymax) ymax = y;
      }
    }
    final dx = (xmax - xmin).abs() < 1e-9 ? 1.0 : (xmax - xmin);
    final dy = (ymax - ymin).abs() < 1e-9 ? 1.0 : (ymax - ymin);
    xmin -= dx * 0.08;
    xmax += dx * 0.08;
    ymin -= dy * 0.12;
    ymax += dy * 0.12;

    double sx(double x) => pad + (x - xmin) / (xmax - xmin) * (size.width - pad - 10);
    double sy(double y) =>
        size.height - pad - (y - ymin) / (ymax - ymin) * (size.height - pad - 12);

    // 网格
    final grid = Paint()..color = gridColor..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final gx = pad + (size.width - pad - 10) * i / 4;
      canvas.drawLine(Offset(gx, 8), Offset(gx, size.height - pad), grid);
      final gy = 8 + (size.height - pad - 12) * i / 4;
      canvas.drawLine(Offset(pad, gy), Offset(size.width - 10, gy), grid);
    }
    // 坐标轴
    final axis = Paint()..color = axisColor..strokeWidth = 1.2;
    canvas.drawLine(Offset(pad, sy(ymin)), Offset(size.width - 10, sy(ymin)), axis);
    canvas.drawLine(Offset(pad, 8), Offset(pad, size.height - pad), axis);

    void label(String t, Offset o) {
      tp.text = TextSpan(text: t, style: TextStyle(fontSize: 9.5, color: labelColor));
      tp.layout();
      tp.paint(canvas, o);
    }
    label(_short(xmin), Offset(pad - 2, sy(ymin) + 2));
    label(_short(xmax), Offset(size.width - 10 - 22, sy(ymin) + 2));
    label(_short(ymax), Offset(2, 8));
    label(_short(ymin), Offset(2, size.height - pad - 10));

    // 拟合曲线（先画，点画在上层）
    if (f != null) {
      final path = Path();
      const m = 160;
      var started = false;
      for (int i = 0; i <= m; i++) {
        final x = xmin + (xmax - xmin) * i / m;
        final y = f(x);
        if (!y.isFinite || y.abs() > 1e12) {
          started = false;
          continue;
        }
        final o = Offset(sx(x), sy(y));
        if (!started) {
          path.moveTo(o.dx, o.dy);
          started = true;
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF2F6BFF)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke);
    }

    // 散点
    final dotPaint = Paint()
      ..color = const Color(0xFFD7263D)
      ..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final p in pts) {
      final o = Offset(sx(p.x), sy(p.y));
      canvas.drawCircle(o, 3.6, dotPaint);
      canvas.drawCircle(o, 3.6, ringPaint);
    }
  }

  static String _short(double v) {
    if (v == 0) return '0';
    if (v.abs() >= 1e5 || v.abs() < 1e-3) return v.toStringAsExponential(2);
    var s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter oldDelegate) =>
      oldDelegate.pts != pts || oldDelegate.fit != fit;
}

/// 求值（x=0 时即普通计算）；抛出 [ExprError]
double evaluate(String src, double x, Map<String, double> params, AngleMode am, double ans) {
  if (src.trim().isEmpty) throw ExprError('表达式为空');
  final node = Parser(src).parse();
  final p = Map<String, double>.from(params);
  p['ans'] = ans;
  return node.eval(x, p, am);
}

/// 收集单字母参数（滑块）
/// 函数名 / 常量 / x / y 除外；变量名保留原始大小写（A 与 a 为不同参数）
Set<String> collectParams(String src) {
  final set = <String>{};
  try {
    for (final t in _tokenize(src)) {
      if (t.type != 'id') continue;
      final low = t.text.toLowerCase();
      if (_functions.containsKey(low) || _hofFns.containsKey(low)) continue;
      if (low == 'pi' || low == 'ans' || low == 'x' || low == 'y') continue;
      if (t.text == 'e') continue; // 小写 e 为自然常数；大写 E 是独立参数
      set.add(t.text);
    }
  } catch (_) {}
  return set;
}

// ============================ 复数与多项式求根 ============================

class _Cx {
  final double re, im;
  const _Cx(this.re, this.im);
  _Cx operator +(_Cx o) => _Cx(re + o.re, im + o.im);
  _Cx operator -(_Cx o) => _Cx(re - o.re, im - o.im);
  _Cx operator *(_Cx o) => _Cx(re * o.re - im * o.im, re * o.im + im * o.re);
  _Cx operator /(_Cx o) {
    final d = o.re * o.re + o.im * o.im;
    return _Cx((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
  }
  double get abs => math.sqrt(re * re + im * im);
}

/// 复系数 Horner 求值
_Cx _polyValCx(List<_Cx> c, _Cx z) {
  var r = const _Cx(0, 0);
  for (final a in c) {
    r = r * z + a;
  }
  return r;
}

/// 复系数 Horner 求导：d/dz Σ c_i z^(n-i)
_Cx _polyDerivCx(List<_Cx> c, _Cx z) {
  var r = const _Cx(0, 0);
  for (int i = 0; i < c.length - 1; i++) {
    r = r * z + c[i] * _Cx((c.length - 1 - i).toDouble(), 0);
  }
  return r;
}

/// 阻尼牛顿法求一个根：步长回退保证 |f| 单调下降，避免发散/震荡
_Cx? _polyNewtonRoot(List<_Cx> c, _Cx start) {
  var z = start;
  for (int it = 0; it < 300; it++) {
    final p = _polyValCx(c, z);
    final d = _polyDerivCx(c, z);
    if (d.abs < 1e-300) return null;
    var step = p / d;
    var nz = z - step;
    for (int k = 0; k < 30; k++) {
      if (_polyValCx(c, nz).abs < p.abs || step.abs < 1e-15) break;
      step = step * const _Cx(0.5, 0);
      nz = z - step;
    }
    if ((nz - z).abs < 1e-13 * math.max(1.0, z.abs)) return nz;
    z = nz;
  }
  return _polyValCx(c, z).abs < 1e-7 * math.max(1.0, z.abs) ? z : null;
}

/// 综合除法降阶：除以 (z - root)
List<_Cx> _polyDeflate(List<_Cx> c, _Cx root) {
  final n = c.length - 1;
  final q = List<_Cx>.filled(n, const _Cx(0, 0));
  var rem = c[0];
  for (int i = 0; i < n; i++) {
    q[i] = rem;
    rem = c[i + 1] + rem * root;
  }
  return q;
}

/// 多项式求全部根（含复根、重根）：阻尼牛顿找根 + 逐项降阶。
/// 相比 Durand-Kerner，重根情形不会因两根重合除零而发散。
List<_Cx> durandKerner(List<double> coeffs) {
  final n = coeffs.length - 1;
  if (n < 1) return [];
  // 首一化（复系数，支持复根降阶后的中间多项式）
  final c0 = _Cx(coeffs.first, 0);
  var poly = coeffs.map((a) => _Cx(a, 0) / c0).toList();
  // 起始点半径取 Cauchy 上界：所有根均在 |z| <= 1 + max|c_i/c_0| 内
  double scale = 1;
  for (int i = 1; i < coeffs.length; i++) {
    final t = (coeffs[i] / coeffs.first).abs();
    if (t > scale) scale = t;
  }
  final R = 1 + scale;
  final starts = <_Cx>[];
  for (int k = 0; k < 7; k++) {
    final th = 2 * math.pi * k / 7;
    starts.add(_Cx(R * math.cos(th), R * math.sin(th)));
  }
  starts.addAll(const [_Cx(0.4, 0.9), _Cx(-1.2, 0.5), _Cx(1.5, -1.1)]);
  final roots = <_Cx>[];
  while (poly.length > 1) {
    _Cx? cand;
    for (final s in starts) {
      cand = _polyNewtonRoot(poly, s);
      if (cand != null) break;
    }
    cand ??= _polyNewtonRoot(poly, const _Cx(0.3, 2.7));
    var found = cand ?? const _Cx(0, 0);
    // 精修 3 步
    for (int k = 0; k < 3; k++) {
      final p = _polyValCx(poly, found);
      final d = _polyDerivCx(poly, found);
      if (d.abs > 1e-300) found = found - p / d;
    }
    roots.add(found);
    poly = _polyDeflate(poly, found);
  }
  // 输出整理：按实部/虚部排序（重根会重复出现，符合数学意义）
  roots.sort((a, b) {
    final c1 = a.re.compareTo(b.re);
    return c1 != 0 ? c1 : a.im.compareTo(b.im);
  });
  return roots;
}

/// 解析系数串：逗号/空格分隔，去除前导零
List<double>? _parseCoeffs(String s) {
  final parts = s.split(RegExp(r'[\s,]+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final nums = <double>[];
  for (final p in parts) {
    final v = double.tryParse(p);
    if (v == null) return null;
    nums.add(v);
  }
  int i = 0;
  while (i < nums.length - 1 && nums[i] == 0) i++;
  return nums.sublist(i);
}

// ============================ 绘图 ============================

class Viewport {
  double xmin, xmax, ymin, ymax;
  Viewport(this.xmin, this.xmax, this.ymin, this.ymax);
  double get dx => xmax - xmin;
  double get dy => ymax - ymin;
}

/// 等比例视口：保持 x 跨度与中心不变，按画布宽高比推导 y 跨度，
/// 保证 x/y 单位的像素长度一致（否则 x²+y²=25 会画成椭圆）。
Viewport fitAspect(Viewport vp, Size size) {
  if (size.width <= 0 || size.height <= 0) return vp;
  final cx = (vp.xmin + vp.xmax) / 2, cy = (vp.ymin + vp.ymax) / 2;
  final dy = vp.dx * size.height / size.width;
  return Viewport(cx - vp.dx / 2, cx + vp.dx / 2, cy - dy / 2, cy + dy / 2);
}

String _fmtTick(double v, double step) {
  if (v == 0) return '0';
  if (v.abs() >= 1e6 || v.abs() < 1e-4) {
    String s = v.toStringAsExponential(1);
    return s;
  }
  final digits = math.max(0, -(math.log(step) / math.ln10).floor() + 1);
  String s = v.toStringAsFixed(math.min(digits, 8));
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

class GraphPainter extends CustomPainter {
  final Viewport vp;
  final List<FnRow> fns;
  final Map<String, double> params;
  final AngleMode angleMode;
  final double ans;
  final Offset? crosshair;
  final Color gridColor, axisColor, labelColor;
  // 读值标注：零点 / 极值 / 交点（可关闭）
  final bool showAnno;
  // 积分面积着色：对第 intFn 条函数在 [intA, intB] 上填充
  final double? intA, intB;
  final int intFn;

  GraphPainter(this.vp, this.fns, this.params, this.angleMode, this.ans, this.crosshair,
      {required this.gridColor,
      required this.axisColor,
      required this.labelColor,
      this.showAnno = false,
      this.intA,
      this.intB,
      this.intFn = 0});

  @override
  void paint(Canvas canvas, Size size) {
    // 等比例视口（遮蔽字段 vp）：保证圆不变形
    final vp = fitAspect(this.vp, size);
    final grid = Paint()..color = gridColor..strokeWidth = 1;
    final axis = Paint()..color = axisColor..strokeWidth = 1.4;
    final tp = TextPainter()..textDirection = TextDirection.ltr;

    double sx(double x) => (x - vp.xmin) / vp.dx * size.width;
    double sy(double y) => size.height - (y - vp.ymin) / vp.dy * size.height;

    final xT = _ticks(vp.dx / 8, (vp.xmin / 1).floorToDouble() * 0 + vp.xmin, vp.xmax);
    final yT = _ticks(vp.dy / 6, vp.ymin, vp.ymax);

    for (final t in xT.values) {
      final px = sx(t);
      if (px >= 0 && px <= size.width) canvas.drawLine(Offset(px, 0), Offset(px, size.height), grid);
    }
    for (final t in yT.values) {
      final py = sy(t);
      if (py >= 0 && py <= size.height) canvas.drawLine(Offset(0, py), Offset(size.width, py), grid);
    }
    final ax = sy(0).clamp(0.0, size.height), ay = sx(0).clamp(0.0, size.width);
    canvas.drawLine(Offset(0, ax), Offset(size.width, ax), axis);
    canvas.drawLine(Offset(ay, 0), Offset(ay, size.height), axis);

    for (final t in xT.values) {
      final px = sx(t);
      if (px < 0 || px > size.width || t == 0) continue;
      _label(canvas, tp, _fmtTick(t, xT.step), Offset(px + 2, ax + 3));
    }
    for (final t in yT.values) {
      final py = sy(t);
      if (py < 0 || py > size.height || t == 0) continue;
      _label(canvas, tp, _fmtTick(t, yT.step), Offset(ay + 4, py - 12));
    }

    // —— 积分面积着色（在曲线之下填充，避免盖住曲线） ——
    if (intA != null && intB != null && intB! > intA! &&
        intFn >= 0 && intFn < fns.length) {
      final fn = fns[intFn];
      if (fn.visible && fn.kind == 'y' && fn.expr.trim().isNotEmpty) {
        final fill = Paint()
          ..color = fn.color.withOpacity(0.20)
          ..style = PaintingStyle.fill;
        final edge = Paint()
          ..color = fn.color.withOpacity(0.55)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
        const m = 160;
        final path = Path();
        var started = false;
        for (int i = 0; i <= m; i++) {
          final x = intA! + (intB! - intA!) * i / m;
          double y;
          try {
            y = evaluate(fn.expr, x, params, angleMode, ans);
          } catch (_) {
            y = double.nan;
          }
          if (!y.isFinite || y.abs() > 1e12) {
            started = false;
            continue;
          }
          if (!started) {
            path.moveTo(sx(x), sy(0));
            path.lineTo(sx(x), sy(y));
            started = true;
          } else {
            path.lineTo(sx(x), sy(y));
          }
        }
        if (started) {
          path.lineTo(sx(intB!), sy(0));
          path.close();
          canvas.drawPath(path, fill);
          canvas.drawPath(path, edge);
        }
        // 上下限竖线
        for (final xv in [intA!, intB!]) {
          canvas.drawLine(Offset(sx(xv), 0), Offset(sx(xv), size.height), edge);
        }
      }
    }

    // 曲线：逐像素采样 + 断笔检测
    final n = math.max(64, size.width.toInt());
    for (final fn in fns) {
      if (!fn.visible || fn.expr.trim().isEmpty) continue;
      final paint = Paint()
        ..color = fn.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (fn.kind == 'implicit') {
        // 隐函数 f(x,y)=0：网格边检测（marching squares 简化）绘制等值线
        // 支持直接写 "x+y=1"，归一化为 "(x+y)-(1)" 后按 f=0 求等值线
        final src = implicitEqSrc(fn.expr);
        const N = 150;
        final fv = List.generate(N + 1, (_) => List<double?>.filled(N + 1, null));
        for (int i = 0; i <= N; i++) {
          final x = vp.xmin + i * vp.dx / N;
          for (int j = 0; j <= N; j++) {
            final y = vp.ymin + j * vp.dy / N;
            try {
              fv[i][j] = evaluate(src, x, <String, double>{'y': y, ...params}, angleMode, ans);
            } catch (_) {
              fv[i][j] = null;
            }
          }
        }
        double X(int i) => vp.xmin + i * vp.dx / N;
        double Y(int j) => vp.ymin + j * vp.dy / N;
        Offset SP(double x, double y) => Offset(sx(x), sy(y));
        final path = Path();
        for (int i = 0; i < N; i++) {
          for (int j = 0; j < N; j++) {
            final f00 = fv[i][j], f10 = fv[i + 1][j], f01 = fv[i][j + 1], f11 = fv[i + 1][j + 1];
            if (f00 == null || f10 == null || f01 == null || f11 == null) continue;
            final pts = <Offset>[];
            if (f00 * f10 < 0) {
              final t = f00 / (f00 - f10);
              pts.add(SP(X(i) + t * (X(i + 1) - X(i)), Y(j)));
            }
            if (f01 * f11 < 0) {
              final t = f01 / (f01 - f11);
              pts.add(SP(X(i) + t * (X(i + 1) - X(i)), Y(j + 1)));
            }
            if (f00 * f01 < 0) {
              final t = f00 / (f00 - f01);
              pts.add(SP(X(i), Y(j) + t * (Y(j + 1) - Y(j))));
            }
            if (f10 * f11 < 0) {
              final t = f10 / (f10 - f11);
              pts.add(SP(X(i + 1), Y(j) + t * (Y(j + 1) - Y(j))));
            }
            if (pts.length == 2) {
              path.moveTo(pts[0].dx, pts[0].dy);
              path.lineTo(pts[1].dx, pts[1].dy);
            }
          }
        }
        canvas.drawPath(path, paint);
        continue;
      }
      // 显式 y = f(x)
      final path = Path();
      bool penUp = true;
      double? pyPrev;
      for (int i = 0; i <= n; i++) {
        final x = vp.xmin + i * vp.dx / n;
        double y;
        try {
          y = evaluate(fn.expr, x, params, angleMode, ans);
        } catch (_) {
          y = double.nan;
        }
        if (y.isNaN || y.isInfinite || y.abs() > 1e12) {
          penUp = true;
          pyPrev = null;
          continue;
        }
        final py = sy(y);
        if (!penUp && pyPrev != null && (py - pyPrev).abs() > size.height * 1.5) {
          // 不连续点（1/x、tan x 等）→ 断笔，不画竖伪线
          penUp = true;
        }
        if (penUp) {
          path.moveTo(sx(x), py);
          penUp = false;
        } else {
          path.lineTo(sx(x), py);
        }
        pyPrev = py;
      }
      canvas.drawPath(path, paint);
    }

    // —— 读值标注：零点 / 极值 / 交点（用 solveRoot + 导数精确求解） ——
    if (showAnno) {
      const maxAnno = 12;
      var annoCount = 0;
      final dotPaint = Paint()..style = PaintingStyle.fill;
      void dot(Offset p, Color c) {
        dotPaint.color = c;
        canvas.drawCircle(p, 3.4, dotPaint);
      }
      void mark(Offset p, Color c, String text) {
        dot(p, c);
        _label(canvas, tp, text, Offset(p.dx + 5, p.dy - 13));
      }
      double fvOf(int idx, double x) {
        try {
          return evaluate(fns[idx].expr, x, params, angleMode, ans);
        } catch (_) {
          return double.nan;
        }
      }
      final m = math.max(200, (size.width * 1.2).toInt());
      final xs = List<double>.generate(m + 1, (i) => vp.xmin + i * vp.dx / m);
      final samples = <List<double>>[];
      for (int fi = 0; fi < fns.length; fi++) {
        final fn = fns[fi];
        if (!fn.visible || fn.kind != 'y' || fn.expr.trim().isEmpty) {
          samples.add(const []);
          continue;
        }
        samples.add([for (final x in xs) fvOf(fi, x)]);
      }

      // ① 零点与极值
      for (int fi = 0; fi < fns.length && annoCount < maxAnno; fi++) {
        final fn = fns[fi];
        if (!fn.visible || fn.kind != 'y' || fn.expr.trim().isEmpty) continue;
        final ys = samples[fi];
        for (int i = 1; i < ys.length && annoCount < maxAnno; i++) {
          final a = ys[i - 1], b = ys[i];
          if (a.isFinite && b.isFinite && a * b < 0) {
            // 变号 → 用 solveRoot 在小区间内精确收敛
            double xz = xs[i];
            try {
              xz = solveRoot((t) => fvOf(fi, t), xs[i - 1], xs[i]);
            } catch (_) {}
            mark(Offset(sx(xz), sy(0)), const Color(0xFFFF5722),
                '零点 (${_fmtCoord(xz)}, 0)');
            annoCount++;
          }
          if (i + 1 < ys.length && annoCount < maxAnno) {
            final c = ys[i + 1];
            // 局部极值：两侧同向 → 导数变号，用导数求根精确化
            if (a.isFinite && b.isFinite && c.isFinite && (b - a) * (b - c) > 0) {
              double xv = xs[i];
              try {
                xv = solveRoot((t) => derivative((u) => fvOf(fi, u), t), xs[i - 1], xs[i + 1]);
              } catch (_) {}
              final yv = fvOf(fi, xv);
              if (yv.isFinite) {
                mark(Offset(sx(xv), sy(yv)), const Color(0xFFD7263D),
                    '${b > a ? '极大' : '极小'} (${_fmtCoord(xv)}, ${_fmtCoord(yv)})');
                annoCount++;
              }
            }
          }
        }
      }

      // ② 两函数交点
      for (int fi = 0; fi < fns.length && annoCount < maxAnno; fi++) {
        for (int fj = fi + 1; fj < fns.length && annoCount < maxAnno; fj++) {
          final af = fns[fi], bf = fns[fj];
          if (!af.visible || !bf.visible || af.kind != 'y' || bf.kind != 'y') continue;
          if (af.expr.trim().isEmpty || bf.expr.trim().isEmpty) continue;
          final ya = samples[fi], yb = samples[fj];
          for (int i = 1; i < ya.length && annoCount < maxAnno; i++) {
            final d0 = ya[i - 1] - yb[i - 1], d1 = ya[i] - yb[i];
            if (d0.isFinite && d1.isFinite && d0 * d1 < 0) {
              double xz = xs[i];
              try {
                xz = solveRoot((t) => fvOf(fi, t) - fvOf(fj, t), xs[i - 1], xs[i]);
              } catch (_) {}
              final yv = fvOf(fi, xz);
              if (yv.isFinite) {
                mark(Offset(sx(xz), sy(yv)), const Color(0xFF0EA57B),
                    '交点 (${_fmtCoord(xz)}, ${_fmtCoord(yv)})');
                annoCount++;
              }
            }
          }
        }
      }
    }

    if (crosshair != null) {
      final p = Paint()..color = const Color(0x99FF5722)..strokeWidth = 1;
      canvas.drawLine(Offset(0, crosshair!.dy), Offset(size.width, crosshair!.dy), p);
      canvas.drawLine(Offset(crosshair!.dx, 0), Offset(crosshair!.dx, size.height), p);
      canvas.drawCircle(crosshair!, 4, Paint()..color = const Color(0xFFFF5722));
    }
  }

  /// 标注坐标格式化：最多 4 位小数，去掉尾随 0
  static String _fmtCoord(double v) {
    if (v == 0) return '0';
    if (v.abs() >= 1e6 || v.abs() < 1e-4) return v.toStringAsExponential(3);
    var t = v.toStringAsFixed(4);
    if (t.contains('.')) {
      t = t.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return t;
  }

  _TickList _ticks(double raw, double lo, double hi) {
    final mag = math.pow(10, (math.log(raw) / math.ln10).floorToDouble()).toDouble();
    final norm = raw / mag;
    final f = norm < 1.5 ? 1.0 : (norm < 3.5 ? 2.0 : (norm < 7.5 ? 5.0 : 10.0));
    final step = f * mag;
    final out = <double>[];
    double t0 = step * (lo / step).floorToDouble();
    for (double t = t0; t <= hi + step; t += step) {
      out.add(t);
      if (out.length > 40) break;
    }
    return _TickList(out, step);
  }

  void _label(Canvas canvas, TextPainter tp, String s, Offset o) {
    tp.text = TextSpan(text: s, style: TextStyle(fontSize: 10, color: labelColor));
    tp.layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant GraphPainter old) => true;
}

class _TickList {
  final List<double> values;
  final double step;
  _TickList(this.values, this.step);
}

// ============================ 状态与界面 ============================

/// iOS 风格圆形/胶囊按键，带按压高亮
class _CalcKey extends StatefulWidget {
  final String label;
  final double width;
  final double height;
  final Color bg;
  final Color fg;
  final double fontSize;
  final FontWeight fontWeight;
  final VoidCallback onTap;
  const _CalcKey({
    super.key,
    required this.label,
    required this.width,
    required this.height,
    required this.bg,
    required this.fg,
    required this.fontSize,
    required this.fontWeight,
    required this.onTap,
  });

  @override
  State<_CalcKey> createState() => _CalcKeyState();
}

class _CalcKeyState extends State<_CalcKey> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _down
        ? Color.alphaBlend(Colors.white.withOpacity(isDark ? 0.28 : 0.55), widget.bg)
        : widget.bg;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(widget.height / 2),
          boxShadow: isDark
              ? null
              : [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 5, offset: const Offset(0, 1))],
        ),
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: widget.fontWeight,
                  color: widget.fg,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistItem {
  final String expr;
  final String result;
  _HistItem(this.expr, this.result);
}

/// 显示区纸带行：按 = 后，已完成的表达式与结果上移为一行（回车换行效果）
class _TapeItem {
  final String expr;
  final String result;
  const _TapeItem(this.expr, this.result);
}

class FnRow {
  String expr;
  Color color;
  bool visible;
  String kind; // 'y' 显式函数 / 'implicit' 隐函数 f(x,y)=0
  FnRow(this.expr, this.color, {this.visible = true, this.kind = 'y'});
}

/// 参数滑块的取值范围（可自动扩展）
class _ParamSpec {
  double min, max;
  _ParamSpec(this.min, this.max);
  /// 保证 v 落在范围内；越界则自动扩展对应侧
  void fit(double v) {
    if (v > max) max = v;
    if (v < min) min = v;
  }
  /// 贴近边界时自动放大范围
  void growIfAtEdge(double v) {
    if (v >= max * 0.995) max = max <= 0 ? 10 : max * 2;
    if (v <= min * 0.995) min = min >= 0 ? -10 : min * 2;
  }
}

/// 隐函数输入归一化："x+y=1" → "(x+y) - (1)"；无等号则原样返回（视为 f(x,y)=0）
String implicitEqSrc(String s) {
  final t = s.trim();
  final k = t.indexOf('=');
  if (k < 0) return t;
  final l = t.substring(0, k).trim(), r = t.substring(k + 1).trim();
  if (l.isEmpty || r.isEmpty) return t.replaceAll('=', '').trim();
  return '($l) - ($r)';
}

const fnPalette = [
  Color(0xFF2F6BFF), Color(0xFF0EA57B), Color(0xFFE8590C),
  Color(0xFF9C36B5), Color(0xFFD7263D), Color(0xFF0E7490),
  Color(0xFF8B8000), Color(0xFF5F0F40),
];

class HomePage extends StatefulWidget {
  final bool dark;
  final VoidCallback onToggleDark;
  const HomePage({super.key, required this.dark, required this.onToggleDark});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int mode = 0; // 0 计算器 1 图形

  // —— 计算器 ——
  final calcCtrl = TextEditingController();
  double ans = 0;
  String calcError = '';
  String calcResult = '';
  bool sciPage = false;
  double? _displayValue; // 当前显示数值（用于进制联动）
  List<_HistItem> _history = [];
  final List<_TapeItem> _tape = []; // 显示区纸带（= 触发换行入带）

  // —— 图形 ——
  final List<TextEditingController> fnCtrls = [];
  final List<FocusNode> fnFocus = [];
  final List<FnRow> fns = [];
  final Map<String, double> paramValues = {};
  final Map<String, _ParamSpec> paramSpecs = {}; // 每个参数的滑块范围（自动扩展）
  int _activeFn = 0;
  Viewport vp = Viewport(-6.5, 6.5, -4.2, 4.2);
  double inputFraction = 0.32;
  bool inputCollapsed = false;
  Offset? crosshair;
  // 图形读值：标注开关 + 积分着色区间
  bool showAnno = false;
  double? intA, intB;
  int intFn = 0;
  // —— 数据拟合 ——
  final dataCtrl = TextEditingController();
  String fitKind = 'linear';
  List<Pt>? _pts;
  FitResult? _fit;
  String dataError = '';
  // 缩放/平移手势起点（用于围绕焦点正确缩放，避免累积误差）
  Viewport? _vpStart;
  Offset? _fpStart;

  @override
  void initState() {
    super.initState();
    calcCtrl.addListener(_onCalcLive);
    _addFn('sin(x)');
    _addFn('a*x^2');
    _restoreState();
  }

  bool _restored = false; // 只读盘完成后才允许回写，避免覆盖掉已有数据
  Timer? _persistTimer;

  /// 合并写入：连续操作时只落盘一次，避免每次按键都写文件
  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 800), _persistState);
  }

  // ================= 持久化 =================
  // 计算历史、纸带、ans、函数表达式与参数值写入本地磁盘，重启后自动恢复。
  static const _kHistory = 'calc_history';
  static const _kTape = 'calc_tape';
  static const _kAns = 'calc_ans';
  static const _kFns = 'graph_fns';
  static const _kData = 'data_text';
  static const _kDataFit = 'data_fit_kind';
  static const _kParamMin = 'graph_param_min';
  static const _kParamMax = 'graph_param_max';

  Future<void> _restoreState() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final rawHist = sp.getString(_kHistory);
      final rawTape = sp.getString(_kTape);
      final rawFns = sp.getString(_kFns);
      final rawData = sp.getString(_kData);
      final rawMin = sp.getString(_kParamMin);
      final rawMax = sp.getString(_kParamMax);
      if (!mounted) return;
      setState(() {
        ans = sp.getDouble(_kAns) ?? 0;
        _restored = true;
        try {
          if (rawHist != null && rawHist.isNotEmpty) {
            _history = (jsonDecode(rawHist) as List)
                .take(50)
                .map((e) => _HistItem('${e[0]}', '${e[1]}'))
                .toList();
          }
          if (rawTape != null && rawTape.isNotEmpty) {
            _tape.addAll((jsonDecode(rawTape) as List)
                .take(30)
                .map((e) => _TapeItem('${e[0]}', '${e[1]}')));
          }
          if (rawFns != null && rawFns.isNotEmpty) {
            final list = jsonDecode(rawFns) as List;
            // 恢复函数列表：替换默认占位的两条
            fnCtrls.clear();
            fns.clear();
            fnFocus.clear();
            for (final e in list) {
              final src = '${e[0]}';
              final kind = e.length > 1 ? '${e[1]}' : (src.contains('=') ? 'implicit' : 'y');
              _addFn(src, kind);
            }
          }
          if (rawData != null) {
            dataCtrl.text = rawData;
            fitKind = sp.getString(_kDataFit) ?? 'linear';
            _parseAndFit();
          }
          if (rawMin != null && rawMax != null) {
            final mins = jsonDecode(rawMin) as Map<String, dynamic>;
            final maxs = jsonDecode(rawMax) as Map<String, dynamic>;
            for (final k in paramValues.keys) {
              final lo = (mins[k] as num?)?.toDouble();
              final hi = (maxs[k] as num?)?.toDouble();
              if (lo != null && hi != null) paramSpecs[k] = _ParamSpec(lo, hi);
            }
          }
        } catch (_) {
          // 数据损坏时静默忽略，保持默认状态
        }
      });
    } catch (_) {
      // 本地存储不可用（如极少数受限环境）时不阻塞使用
    }
  }

  Future<void> _persistState() async {
    if (!_restored) return; // 尚未读盘就写入会把历史抹掉
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_kAns, ans);
      await sp.setString(
        _kHistory,
        jsonEncode(_history.take(50).map((h) => [h.expr, h.result]).toList()),
      );
      await sp.setString(
        _kTape,
        jsonEncode(_tape.length > 30
            ? _tape.sublist(_tape.length - 30).map((t) => [t.expr, t.result]).toList()
            : _tape.map((t) => [t.expr, t.result]).toList()),
      );
      await sp.setString(
        _kFns,
        jsonEncode(<List<String>>[
          for (int i = 0; i < fnCtrls.length; i++) [fnCtrls[i].text, fns[i].kind],
        ]),
      );
      await sp.setString(_kData, dataCtrl.text);
      await sp.setString(_kDataFit, fitKind);
      await sp.setString(
        _kParamMin,
        jsonEncode(<String, double>{
          for (final e in paramSpecs.entries) e.key: e.value.min,
        }),
      );
      await sp.setString(
        _kParamMax,
        jsonEncode(<String, double>{
          for (final e in paramSpecs.entries) e.key: e.value.max,
        }),
      );
    } catch (_) {
      // 写入失败不影响交互
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    if (_restored) _persistState(); // 退出前落盘
    for (final c in fnCtrls) {
      c.dispose();
    }
    for (final f in fnFocus) {
      f.dispose();
    }
    calcCtrl.dispose();
    dataCtrl.dispose();
    super.dispose();
  }

  void _addFn([String expr = '', String kind = '']) {
    final c = TextEditingController(text: expr);
    c.addListener(_onFnChanged);
    final idx = fnFocus.length;
    final fn = FocusNode();
    fn.addListener(() {
      if (fn.hasFocus) setState(() => _activeFn = idx);
    });
    fnFocus.add(fn);
    fnCtrls.add(c);
    fns.add(FnRow(expr, fnPalette[fns.length % fnPalette.length],
        kind: kind.isEmpty ? 'y' : kind));
    _onFnChanged();
  }

  void _removeFn(int i) {
    fnCtrls[i].dispose();
    fnFocus[i].dispose();
    fnCtrls.removeAt(i);
    fnFocus.removeAt(i);
    fns.removeAt(i);
    if (_activeFn >= fnFocus.length) _activeFn = fnFocus.length - 1;
    if (_activeFn < 0) _activeFn = 0;
    _onFnChanged();
  }

  // 在「当前聚焦」的函数输入框光标处插入符号
  void _insertSym(String insert) {
    if (_activeFn < 0 || _activeFn >= fnCtrls.length) return;
    final ctrl = fnCtrls[_activeFn];
    final base = ctrl.text;
    final sel = ctrl.selection;
    final pos = sel.isValid && sel.start >= 0 && sel.start <= base.length ? sel.start : base.length;
    final ns = base.substring(0, pos) + insert + base.substring(pos);
    ctrl.value = TextEditingValue(
      text: ns,
      selection: TextSelection.collapsed(offset: pos + insert.length),
    );
    fnFocus[_activeFn].requestFocus();
    _onFnChanged();
  }

  /// 切换函数模式：显式 y=f(x) ↔ 隐式 F(x,y)=0
  /// 切到隐式时自动改写为 F(x,y)=0 形式：
  ///   - 原式含 "="  → 保持不变（如 x^2+y^2=25）
  ///   - 原式含 y   → 追加 "=0"（如 x+y → x+y=0）
  ///   - 原式不含 y → 改写为 "y-(原式)=0"（如 x^2-1 → y-(x^2-1)=0）
  /// 切回显式时，去掉自动补上的 "=0"，并把 "y-(...)" 还原为 "..."
  void _toggleFnKind(int i) {
    String? tip;
    setState(() {
      final toImplicit = fns[i].kind == 'y';
      fns[i].kind = toImplicit ? 'implicit' : 'y';
      final txt = fnCtrls[i].text.trim();
      if (toImplicit) {
        if (txt.isEmpty) {
          // 空表达式：给个默认示例，用户一看就懂隐式怎么写
          fnCtrls[i].text = 'x^2+y^2=9';
          tip = '已填入隐式示例 x²+y²=9，修改左侧表达式即可';
        } else if (txt.contains('=')) {
          // 已经是等式形式，保持不变
        } else if (_containsVar(txt, 'y')) {
          fnCtrls[i].text = '$txt=0';
        } else {
          fnCtrls[i].text = 'y-($txt)=0';
        }
      } else {
        // 切回显式：还原成 y=f(x)
        var s = txt;
        if (s.endsWith('=0')) s = s.substring(0, s.length - 2).trim();
        final m = RegExp(r'^y-\((.*)\)$').firstMatch(s);
        if (m != null) s = m.group(1)!;
        fnCtrls[i].text = s;
      }
    });
    _onFnChanged();
    final msg = tip;
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// 表达式中是否出现指定变量（忽略大小写、排除函数名）
  bool _containsVar(String src, String name) {
    try {
      for (final t in _tokenize(src)) {
        if (t.type != 'id') continue;
        if (t.text.toLowerCase() == name) return true;
      }
    } catch (_) {}
    return false;
  }

  void _onFnChanged() {
    for (int i = 0; i < fnCtrls.length; i++) {
      fns[i].expr = fnCtrls[i].text;
      // 输入含 "=" 时自动切为隐函数模式（如 x+y=1、x^2+y^2=25）
      if (fnCtrls[i].text.contains('=') && fns[i].kind == 'y') {
        fns[i].kind = 'implicit';
      }
    }
    final used = <String>{};
    for (int i = 0; i < fnCtrls.length; i++) {
      final src = fns[i].kind == 'implicit' ? implicitEqSrc(fnCtrls[i].text) : fnCtrls[i].text;
      used.addAll(collectParams(src));
    }
    for (final k in used) {
      if (!paramValues.containsKey(k)) {
        paramValues[k] = 1;
        paramSpecs[k] = _ParamSpec(-10, 10);
      }
    }
    paramValues.removeWhere((k, _) => k == 'y' || !used.contains(k));
    paramSpecs.removeWhere((k, _) => !used.contains(k));
    setState(() {});
  }

  AngleMode get _angleMode => deg ? AngleMode.deg : AngleMode.rad;

  // ================= 计算器 =================
  bool deg = true;

  static const keysBasic = [
    ['C', '⌫', 'ans', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
    ['0', '.', '=|2'],
  ];
  static const keysSci = [
    ['sin(', 'cos(', 'tan(', '^'],
    ['asin(', 'acos(', 'atan(', 'x!'],
    ['ln(', 'log(', '√(', 'π'],
    ['(', ')', 'e', 'x'],
  ];

  void _press(String k) {
    setState(() {
      calcError = '';
      if (k == 'C') {
        calcCtrl.clear();
        calcResult = '';
      } else if (k == '⌫') {
        final s = calcCtrl.text;
        if (s.isNotEmpty) calcCtrl.text = s.substring(0, s.length - 1);
      } else if (k == '=') {
        _equals();
      } else {
        final ins = k
            .replaceAll('×', '*')
            .replaceAll('÷', '/')
            .replaceAll('−', '-')
            .replaceAll('√', 'sqrt')
            .replaceAll('π', 'pi')
            .replaceAll('x!', '!');
        calcCtrl.value = TextEditingValue(
          text: calcCtrl.text + ins,
          selection: TextSelection.collapsed(offset: calcCtrl.text.length + ins.length),
        );
      }
    });
  }

  // 实时计算：输入即预览结果（不更新 ans、不记历史、不报错提示）
  void _onCalcLive() {
    final src = calcCtrl.text.trim();
    if (src.isEmpty) {
      if (calcResult.isNotEmpty || _displayValue != null) {
        setState(() {
          calcResult = '';
          _displayValue = null;
        });
      }
      return;
    }
    try {
      final r = evaluate(src, 0, {}, _angleMode, ans);
      setState(() {
        calcResult = _fmtNum(r);
        _displayValue = r;
      });
    } on ExprError {
      if (calcResult.isNotEmpty || _displayValue != null) {
        setState(() {
          calcResult = '';
          _displayValue = null;
        });
      }
    } catch (_) {
      if (calcResult.isNotEmpty || _displayValue != null) {
        setState(() {
          calcResult = '';
          _displayValue = null;
        });
      }
    }
  }

  void _equals() {
    final src = calcCtrl.text.trim();
    if (src.isEmpty) return;
    try {
      final r = evaluate(src, 0, {}, _angleMode, ans);
      final rs = _fmtNum(r);
      // = 的语义：提交当前行（入纸带）并换行开始新输入
      calcCtrl.clear(); // 触发监听清空实时预览
      setState(() {
        ans = r;
        calcResult = rs; // 等号后仍展示本次结果
        _displayValue = r;
        calcError = '';
        _tape.add(_TapeItem(src, rs));
        if (_tape.length > 30) _tape.removeAt(0);
      });
      _addHistory(src, rs);
      _schedulePersist();
    } on ExprError catch (e) {
      setState(() => calcError = e.message);
    } catch (_) {
      setState(() => calcError = '表达式错误');
    }
  }

  void _addHistory(String expr, String result) {
    setState(() {
      _history.insert(0, _HistItem(expr, result));
      if (_history.length > 50) _history.removeLast();
    });
    _schedulePersist();
  }

  String _fmtNum(double r) {
    if (r.isNaN) return '未定义';
    if (r.isInfinite) return r > 0 ? '∞' : '−∞';
    if (r == r.roundToDouble() && r.abs() < 1e15) return r.round().toString();
    if (r.abs() >= 1e10 || r.abs() < 1e-8) return r.toStringAsExponential(6);
    String s = r.toStringAsFixed(10);
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  // 进制联动展示：基于当前 DEC 结果，展示 HEX/OCT/BIN，点击复制
  /// 结果是否可用进制表示（安全整数）—— 与 _baseRow 内部判断保持一致
  bool _canShowBase(double? v) =>
      v != null && v.isFinite && v == v.roundToDouble() && v.abs() < 9007199254740992;

  Widget _baseRow(double r) {
    if (!_canShowBase(r)) {
      return const SizedBox.shrink();
    }
    final n = r.round();
    final hex = n.toRadixString(16).toUpperCase();
    final oct = n.toRadixString(8);
    final bin = _groupBits(n.toRadixString(2));
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String lab, String val) => GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: val.replaceAll(' ', '')));
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(duration: const Duration(seconds: 1), content: Text('已复制 $lab: $val')),
            );
          },
          child: Container(
            height: 24,
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Row(children: [
              Text('$lab ', style: TextStyle(fontSize: 11, color: scheme.outline)),
              // 不再加 Expanded+ellipsis：完整显示，过长时整行横向滑动
              Text(val,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [chip('HEX', hex), chip('OCT', oct), chip('BIN', bin)]),
      ),
    );
  }

  /// 二进制按字节（8 位）从低位起空格分组，便于阅读。如 85555 → "1 01001110 00110011"
  static String _groupBits(String raw) {
    final neg = raw.startsWith('-');
    final b = neg ? raw.substring(1) : raw;
    if (b.length <= 8) return raw;
    final head = b.length % 8;
    final sb = StringBuffer(neg ? '-' : '');
    sb.write(b.substring(0, head == 0 ? 8 : head));
    for (int i = (head == 0 ? 8 : head); i < b.length; i += 8) {
      sb.write(' ');
      sb.write(b.substring(i, i + 8 > b.length ? b.length : i + 8));
    }
    return sb.toString();
  }

  /// 纸带单行：灰色小字，历史不抢当前结果的视线（主色只留给当前结果）
  static const double _tapeLineH = 17;

  Widget _tapeLine(_TapeItem t) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${t.expr} = ', style: TextStyle(fontSize: 12, color: scheme.outline)),
          TextSpan(
              text: t.result,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withOpacity(0.72),
              )),
        ]),
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // —— iOS 风格键盘：圆形键 / 橙色运算符 / 差异化尺寸 ——
  static const _opKeys = {'+', '−', '×', '÷', '=', '^'};
  static const _funcKeys = {
    'C', '⌫', 'ans', '(', ')', 'π', 'e', 'x', 'x!',
    'sin(', 'cos(', 'tan(', 'asin(', 'acos(', 'atan(', 'ln(', 'log(', '√(',
  };

  // 图形页符号条：[显示标签, 实际插入文本]
  static const _symbols = [
    ['x', 'x'], ['^', '^'], ['x²', '^2'], ['√', 'sqrt('], ['π', 'pi'], ['e', 'e'],
    ['sin(', 'sin('], ['cos(', 'cos('], ['tan(', 'tan('], ['ln(', 'ln('],
    ['(', '('], [')', ')'], ['+', '+'], ['−', '-'], ['×', '*'], ['÷', '/'],
  ];

  Widget _keypad() {
    final rows = sciPage ? keysSci : keysBasic;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final digitBg = isDark ? const Color(0xFF333333) : Colors.white;
    final funcBg = isDark ? const Color(0xFFA5A5A5) : const Color(0xFFD1D1D6);
    const opBg = Color(0xFFFF9F0A);
    final digitFg = isDark ? Colors.white : Colors.black;
    final funcFg = Colors.black;

    return LayoutBuilder(builder: (ctx, box) {
      const gap = 10.0;
      final cell = math.min(
        (box.maxWidth - gap * 5) / 4,
        (box.maxHeight - gap * (rows.length + 1)) / rows.length,
      );
      Widget k(String raw) {
        final parts = raw.split('|');
        final label = parts[0];
        final units = parts.length > 1 ? int.parse(parts[1]) : 1;
        final isOp = _opKeys.contains(label);
        final isFunc = _funcKeys.contains(label);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: gap / 2),
          child: _CalcKey(
            key: ValueKey('calcKey_$label'),
            label: label,
            width: cell * units + gap * (units - 1),
            height: cell,
            bg: isOp ? opBg : (isFunc ? funcBg : digitBg),
            fg: isOp ? Colors.white : (isFunc ? funcFg : digitFg),
            fontSize: isOp ? (label == '=' ? cell * 0.58 : cell * 0.44) : (isFunc ? cell * 0.30 : cell * 0.42),
            fontWeight: isOp ? (label == '=' ? FontWeight.w700 : FontWeight.w500) : FontWeight.w400,
            onTap: () => _press(label),
          ),
        );
      }

      // 左右滑动切换科学/基本键盘（与切换按钮等效）
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 350) setState(() => sciPage = !sciPage);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: gap / 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [for (final label in row) k(label)],
                ),
              ),
          ],
        ),
      );
    });
  }

  /// 是否启用宽屏分栏。用窗口尺寸（宽/高比）判定而不是 body 尺寸：
  /// body 会被 AppBar / 导航栏挤压，导致竖屏手机的显示区看起来也「偏宽」。
  /// 另外收紧到 1.5，避免 800×600 这类近似正方形的窗口被误判为横屏。
  bool get _wideLayout {
    final s = MediaQuery.of(context).size;
    return s.width >= 480 && s.width / s.height >= 1.5;
  }

  Widget _calcPage() {
    if (_wideLayout) {
        // 宽屏：左侧「显示区 + 常驻历史」，右侧「工具栏 + 键盘」
        return Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(children: [
                Expanded(flex: 5, child: _calcDisplay()),
                const Divider(height: 1),
                Expanded(flex: 5, child: _historyPane()),
              ]),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 6,
              child: Column(children: [
                _calcToolbar(),
                Expanded(child: _keypad()),
              ]),
            ),
          ],
        );
      }
      return Column(
        children: [
          Expanded(flex: 4, child: _calcDisplay()),
          const Divider(height: 1),
          _calcToolbar(),
          // 键盘区
          Expanded(flex: 8, child: _keypad()),
        ],
      );
  }

  /// 显示区（方案 A · Google 双行式）：元信息 → 历史灰字 → 表达式 → 结果大字 → 进制
  /// 高度按「预算」精确分配，任何屏幕尺寸下都不溢出、不留空行
  Widget _calcDisplay() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
      child: LayoutBuilder(builder: (ctx, box) {
        final avail = box.maxHeight;
        // 各段标称高度
        double metaH = 18;
        double exprH = 46;
        double resH = calcResult.isEmpty ? 6 : 44;
        double baseH = _canShowBase(_displayValue) ? 30 : 0;
        // 空间不够时按「元信息 → 结果字号 → 进制 → 表达式」降级：
        // 进制行是用户明确需要的信息，优先级高于 ans 元信息行
        if (metaH + exprH + resH + baseH > avail) metaH = 0;
        if (metaH + exprH + resH + baseH > avail) resH = math.min(resH, 34);
        if (metaH + exprH + resH + baseH > avail) baseH = 0;
        if (metaH + exprH + resH > avail) {
          exprH = math.max(28, avail - metaH - resH);
        }
        // 剩余空间留给历史纸带，最多 3 行，按整行取高（避免半行残片）
        final tapeBud = (avail - metaH - exprH - resH - baseH).clamp(0.0, 54.0);
        final rows = math.min(_tape.length, (tapeBud / _tapeLineH).floor()).clamp(0, 3);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // ① 元信息行：ans 与历史条数；DEG/RAD 已统一到标题栏，不再重复
            if (metaH > 0)
              SizedBox(
                height: metaH,
                child: Row(children: [
                  Text('ans = ${_fmtNum(ans)}',
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                  const Spacer(),
                  if (_tape.isNotEmpty)
                    Text('${_tape.length} 条历史',
                        style: TextStyle(fontSize: 11, color: scheme.outline.withOpacity(0.8))),
                ]),
              ),
            // ② 历史纸带：灰色小字，按实际行数取高，不撑满、不留空档
            if (rows > 0)
              SizedBox(
                height: rows * _tapeLineH,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [for (final t in _tape.reversed.take(rows)) _tapeLine(t)],
                  ),
                ),
              ),
            // ③ 当前表达式（中等字号，主输入行）
            SizedBox(
              height: exprH,
              child: TextField(
                controller: calcCtrl,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
                keyboardType: TextInputType.none,
                showCursor: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '0',
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            // ④ 当前结果（主显示）：有结果才占位，空时收起，避免留下一段空行
            AnimatedContainer(
              key: const Key('calcResultBox'),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              height: resH,
              alignment: Alignment.centerRight,
              child: calcResult.isEmpty
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        calcResult,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                          height: 1.15,
                        ),
                      ),
                    ),
            ),
            if (calcError.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Text('⚠ $calcError',
                    style: const TextStyle(fontSize: 13, color: Color(0xFFD7263D))),
              ),
            // ⑤ 进制附加表示：整数结果时固定显示，不再被上方内容挤压掉
            if (baseH > 0) SizedBox(height: baseH, child: _baseRow(_displayValue!)),
          ],
        );
      }),
    );
  }

  /// 横屏左侧常驻的历史列表（点击回填表达式）
  Widget _historyPane() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 2),
          child: Row(children: [
            Text('计算历史',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.outline)),
            const Spacer(),
            if (_history.isNotEmpty)
              SizedBox(
                height: 28,
                child: TextButton(
                  onPressed: () => setState(() {
                    _history.clear();
                    _schedulePersist();
                  }),
                  child: const Text('清空', style: TextStyle(fontSize: 12)),
                ),
              ),
          ]),
        ),
        Expanded(
          child: _history.isEmpty
              ? Center(
                  child: Text('暂无记录',
                      style: TextStyle(fontSize: 12, color: scheme.outline)))
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final h = _history[i];
                    return ListTile(
                      dense: true,
                      title: Text('${h.expr} = ${h.result}', style: const TextStyle(fontSize: 13)),
                      onTap: () => setState(() => calcCtrl.text = h.expr),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 工具栏：键盘切换 / 微积分 / 多项式求根
  Widget _calcToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => sciPage = !sciPage),
            icon: Icon(sciPage ? Icons.calculate_outlined : Icons.functions, size: 18),
            label: Text(sciPage ? '基本键盘' : '科学键盘', style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('toolCalculus'),
            onPressed: _showCalculus,
            icon: const Icon(Icons.area_chart, size: 20),
            tooltip: '微积分 / 方程求根',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          ),
          const SizedBox(width: 2),
          TextButton.icon(
            onPressed: _showPolyRoots,
            icon: const Icon(Icons.auto_graph, size: 18),
            label: const Text('多项式求根', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }


  /// 微积分 / 方程求根对话框：生成 integral / diff / solve 表达式并回填输入框，
  /// 让用户不必记忆语法，同时能在输入框里看到并继续编辑生成的字符串。
  void _showCalculus() {
    final exprCtrl = TextEditingController(text: calcCtrl.text.trim().isEmpty ? 'x^2' : calcCtrl.text.trim());
    final aCtrl = TextEditingController(text: '0');
    final bCtrl = TextEditingController(text: '1');
    String op = 'integral';

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setSt) {
          final isDiff = op == 'diff';
          final labelA = isDiff ? '求值点 x =' : (op == 'integral' ? '积分下限 a =' : '区间左端 a =');
          final labelB = op == 'integral'
              ? '积分上限 b ='
              : (op == 'solve' ? '区间右端 b =' : '步长 h（留空自动）');
          String preview() {
            final e = exprCtrl.text.trim().isEmpty ? 'x^2' : exprCtrl.text.trim();
            final a = aCtrl.text.trim().isEmpty ? '0' : aCtrl.text.trim();
            final b = bCtrl.text.trim();
            if (op == 'integral') return 'integral($e,$a,$b)';
            if (op == 'diff') return b.isEmpty ? 'diff($e,$a)' : 'diff($e,$a,$b)';
            return 'solve($e,$a,$b)';
          }

          return AlertDialog(
            title: const Text('微积分 / 方程求根'),
            content: SizedBox(
              width: 320,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: op,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '运算', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'integral', child: Text('定积分 ∫ f(x) dx')),
                    DropdownMenuItem(value: 'diff', child: Text('导数 f′(x)')),
                    DropdownMenuItem(value: 'solve', child: Text('求零点 f(x) = 0')),
                  ],
                  onChanged: (v) => setSt(() {
                    op = v ?? 'integral';
                    if (op == 'diff') {
                      aCtrl.text = '0';
                      bCtrl.text = '';
                    } else if (op == 'integral') {
                      aCtrl.text = '0';
                      bCtrl.text = '1';
                    } else {
                      aCtrl.text = '0';
                      bCtrl.text = '5';
                    }
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: exprCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '表达式（自变量用 x）',
                    hintText: '如 sin(x)、x^2/2',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setSt(() {}),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: aCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(labelText: labelA, border: const OutlineInputBorder()),
                      onChanged: (_) => setSt(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: bCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(labelText: labelB, border: const OutlineInputBorder()),
                      onChanged: (_) => setSt(() {}),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    preview(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
              TextButton(
                onPressed: () {
                  final built = preview();
                  Navigator.of(ctx).pop();
                  setState(() {
                    calcCtrl.value = TextEditingValue(
                      text: built,
                      selection: TextSelection.collapsed(offset: built.length),
                    );
                  });
                },
                child: const Text('生成'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 多项式求对话框：输入系数 → Durand-Kerner 求全部根
  void _showPolyRoots() {
    final ctrl = TextEditingController();
    final results = <String>[];
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('多项式求根'),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('输入系数（从高次到常数，逗号/空格分隔）：', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '如 1,-2,1,-1', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              if (results.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in results)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text(
                            r,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
            TextButton(
              onPressed: () {
                final coeffs = _parseCoeffs(ctrl.text);
                if (coeffs == null || coeffs.length < 2) {
                  setSt(() {
                    results.clear();
                    results.add('系数格式有误（至少两项，且为数字）');
                  });
                  return;
                }
                final roots = durandKerner(coeffs);
                setSt(() => results
                  ..clear()
                  ..addAll(roots.map((r) {
                    if (r.im.abs() < 1e-9) return 'x ≈ ${_fmtNum(r.re)}';
                    return 'x ≈ ${_fmtNum(r.re)} ${r.im >= 0 ? '+' : '−'} ${_fmtNum(r.im.abs())}i';
                  })));
              },
              child: const Text('求解'),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 图形 =================

  /// 符号条标签的排版：数学量（变量 x、常量 e / π、幂 x²）用公式字体渲染
  /// （衬线 + 斜体，贴近 TeX / 教科书排版），运算符与函数名保持正体无衬线，
  /// 这样 x 与乘号 × 在字形上天然区分开。
  Widget _symLabel(String label) {
    const mathFamily = 'serif';
    const mathStyle = TextStyle(
      fontFamily: mathFamily,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
      height: 1.0,
    );
    switch (label) {
      case 'x':
        return const Text('x', style: TextStyle(
          fontFamily: mathFamily,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          fontSize: 24,
          height: 1.0,
        ));
      case 'x²':
        // 数学排版惯例：底数斜体、指数正体
        return const Text.rich(
          TextSpan(children: [
            TextSpan(
              text: 'x',
              style: TextStyle(fontFamily: mathFamily, fontStyle: FontStyle.italic, fontSize: 22),
            ),
            TextSpan(
              text: '²',
              style: TextStyle(fontFamily: mathFamily, fontStyle: FontStyle.normal, fontSize: 22),
            ),
          ]),
          style: TextStyle(fontWeight: FontWeight.w500, height: 1.0),
        );
      case 'e':
      case 'π':
        return Text(label, style: mathStyle.copyWith(fontSize: 22));
      default:
        return Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.0));
    }
  }

  /// 参数面板：从函数表达式自动提取参数，按 2 列网格排列（不超出页面），
  /// 每个参数滑块范围自适应扩展，点击数值可直接输入精确值。
  /// [availH] 为输入区中参数面板可用的最大高度，超出部分内部滚动。
  Widget _paramPanel(double availH) {
    if (paramValues.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final keys = paramValues.keys.toList();
    // 每行 2 个参数
    final rows = (keys.length / 2).ceil();
    final natural = rows * _paramCellH + 6;
    final h = natural < availH ? natural : availH;
    if (h <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: h,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: LayoutBuilder(builder: (ctx, bc) {
            final cellW = (bc.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                for (final k in keys)
                  SizedBox(
                    width: cellW,
                    child: _paramCell(k, scheme),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// 单个参数单元格的高度（名称行 + 滑块）
  static const double _paramCellH = 40;

  /// 单个参数控件：名称 + 数值（可点击编辑）+ 滑块（范围自动扩展）
  Widget _paramCell(String k, ColorScheme scheme) {
    final v = paramValues[k] ?? 0;
    final spec = paramSpecs[k] ?? _ParamSpec(-10, 10);
    final lo = spec.min < v ? spec.min : v;
    final hi = spec.max > v ? spec.max : v;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Text(k, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => _editParam(k),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _fmtParam(v),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ]),
        SizedBox(
          height: 22,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              min: lo,
              max: hi == lo ? lo + 1 : hi,
              value: v.clamp(lo, hi == lo ? lo + 1 : hi),
              onChanged: (nv) {
                setState(() {
                  paramValues[k] = nv;
                  paramSpecs[k] = spec;
                  // 拖到边缘时自动扩大范围
                  spec.growIfAtEdge(nv);
                });
                _schedulePersist();
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 参数数值格式化：整数不带小数点，小数最多 3 位
  String _fmtParam(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toStringAsFixed(0);
    }
    var s = v.toStringAsFixed(3);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// 点击参数数值 → 弹出精确输入
  Future<void> _editParam(String k) async {
    final ctrl = TextEditingController(text: _fmtParam(paramValues[k] ?? 0));
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('设置参数 $k'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(labelText: '数值', hintText: '可输入负数或小数'),
          onSubmitted: (s) => Navigator.of(ctx).pop(double.tryParse(s)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(double.tryParse(ctrl.text)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (res == null || !res.isFinite) return;
    final spec = paramSpecs[k] ?? _ParamSpec(-10, 10);
    setState(() {
      paramValues[k] = res;
      spec.fit(res);
      paramSpecs[k] = spec;
    });
  }

  Widget _graphPage() {
    return LayoutBuilder(builder: (ctx, outer) {
      // 宽屏：左侧常驻输入区（符号条 / 函数 / 参数），右侧绘图区
      if (_wideLayout) {
        final leftW = (outer.maxWidth * 0.36).clamp(180.0, 320.0);
        return Row(children: [
          SizedBox(width: leftW, child: _graphInput(outer.maxHeight)),
          const VerticalDivider(width: 1),
          Expanded(child: _graphCanvas()),
        ]);
      }
      final scheme = Theme.of(context).colorScheme;
      final bodyH = outer.maxHeight;
      final inputH = bodyH * (inputCollapsed ? 0.07 : inputFraction);
      return Column(children: [
        _graphInput(inputH),
        // 可拖动分隔条（宽屏为左右分栏，无需此条）
        GestureDetector(
          key: const Key('graphDivider'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) {
            setState(() {
              inputFraction = (inputFraction + d.delta.dy / bodyH).clamp(0.25, 0.55);
            });
          },
          child: Container(
            height: 18,
            color: scheme.surfaceVariant.withOpacity(0.5),
            child: Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: scheme.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ),
        // 绘图区
        Expanded(child: _graphCanvas()),
      ]);
    });
  }

  /// 图形页输入区：符号条 → 列表头 → 函数列表 → 参数面板
  Widget _graphInput(double inputH) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: inputH,
      child: LayoutBuilder(builder: (ctx, inner) {
            // 输入区高度有限，按「符号条 → 列表头 → 函数列表 → 参数面板」顺序分配，
            // 保证任何高度下都不溢出（参数面板空间不足时内部滚动）
            final avail = inner.maxHeight;
            final symH = inputCollapsed ? 0.0 : 54.0;
            final headH = (inputCollapsed ? 36.0 : 48.0).clamp(0.0, avail);
            final rest = (avail - symH - headH).clamp(0.0, double.infinity);
            final natural = paramValues.isEmpty
                ? 0.0
                : ((paramValues.length / 2).ceil() * _paramCellH + 6);
            const minListH = 42.0;
            final paramH = natural <= 0
                ? 0.0
                : (rest - minListH).clamp(0.0, natural);
            final listH = (rest - paramH).clamp(0.0, double.infinity);
            return Column(
              children: [
                if (symH > 0)
                  SizedBox(
                    height: symH,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                    child: Row(children: [
                      for (final s in _symbols)
                        // 自绘大号点击目标：比紧凑 ActionChip 更易点中，
                        // HitTestBehavior.opaque 让整块区域（含内边距）都响应点击
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _insertSym(s[1]),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 46),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceVariant.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            alignment: Alignment.center,
                            child: _symLabel(s[0]),
                          ),
                        ),
                    ]),
                  ),
                ),
                SizedBox(
                  height: headH,
                  child: Row(children: [
                    IconButton(
                      icon: Icon(inputCollapsed ? Icons.expand_more : Icons.expand_less, size: 20),
                      tooltip: inputCollapsed ? '展开输入区' : '折叠输入区',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      onPressed: () => setState(() => inputCollapsed = !inputCollapsed),
                    ),
                    if (!inputCollapsed)
                      Text('函数列表', style: TextStyle(fontSize: 13, color: scheme.outline)),
                    const Spacer(),
                    if (!inputCollapsed)
                      IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: '新增函数',
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                        onPressed: () => _addFn(),
                      ),
                  ]),
                ),
                if (!inputCollapsed)
                  SizedBox(
                    height: listH,
                    child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: fnCtrls.length,
                    itemBuilder: (ctx, i) {
                      final fn = fns[i];
                      return SizedBox(
                        height: 42,
                        child: Row(children: [
                          GestureDetector(
                            onTap: () => setState(() => fn.visible = !fn.visible),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(
                                fn.visible ? Icons.circle : Icons.radio_button_unchecked,
                                size: 18,
                                color: fn.color,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: fn.kind == 'y'
                                ? '当前：显式函数 y = f(x)\n点击切换为隐式 F(x,y) = 0'
                                : '当前：隐式函数 F(x,y) = 0\n点击切换为显式 y = f(x)',
                            child: GestureDetector(
                              onTap: () => _toggleFnKind(i),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: fn.kind == 'y'
                                      ? scheme.surfaceVariant.withOpacity(0.6)
                                      : scheme.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: fn.kind == 'implicit'
                                      ? Border.all(color: fn.color.withOpacity(0.6))
                                      : null,
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(
                                    fn.kind == 'y' ? Icons.show_chart : Icons.blur_circular,
                                    size: 14,
                                    color: fn.kind == 'y' ? scheme.outline : fn.color,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    fn.kind == 'y' ? 'y=f(x)' : 'F(x,y)=0',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: fn.kind == 'y' ? scheme.outline : fn.color,
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: fnCtrls[i],
                              focusNode: fnFocus[i],
                              style: TextStyle(fontSize: 15, color: fn.color),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                hintText: '如 x^2-1 或 x^2+y^2=1',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => _removeFn(i),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
                if (paramH > 0) _paramPanel(paramH),
              ],
            );
          }),
    );
  }

  /// 图形页绘图区：缩放 / 平移 / 双击复位 / 点击取值
  Widget _graphCanvas() {
    return LayoutBuilder(builder: (ctx, box) {
              final isDark = Theme.of(ctx).brightness == Brightness.dark;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tapGraph(d.localPosition, box),
                onScaleStart: (d) {
                  _vpStart = Viewport(vp.xmin, vp.xmax, vp.ymin, vp.ymax);
                  _fpStart = d.localFocalPoint;
                  setState(() => crosshair = null);
                },
                onScaleUpdate: (d) => _scaleGraph(d, box),
                onDoubleTap: () => setState(() => vp = Viewport(-6.5, 6.5, -4.2, 4.2)),
                child: CustomPaint(
                  key: const Key('graphCanvas'),
                  size: box.biggest,
                  painter: GraphPainter(
                    vp, fns, paramValues, _angleMode, ans, crosshair,
                    gridColor: isDark ? const Color(0x228090A0) : const Color(0x228090A0),
                    axisColor: isDark ? const Color(0xAA9AA8BC) : const Color(0xAA607080),
                    labelColor: isDark ? const Color(0xFF9AA8BC) : const Color(0xFF7A8699),
                    showAnno: showAnno,
                    intA: intA,
                    intB: intB,
                    intFn: intFn,
                  ),
                ),
              );
    });
  }

  void _tapGraph(Offset local, BoxConstraints box) {
    final v = fitAspect(vp, Size(box.maxWidth, box.maxHeight));
    final x = v.xmin + local.dx / box.maxWidth * v.dx;
    double bestDist = double.infinity;
    double? bestY;
    for (final fn in fns) {
      if (!fn.visible || fn.expr.trim().isEmpty) continue;
      try {
        final y = evaluate(fn.expr, x, paramValues, _angleMode, ans);
        if (y.isNaN || y.isInfinite) continue;
        final py = box.maxHeight - (y - v.ymin) / v.dy * box.maxHeight;
        final dist = (py - local.dy).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestY = y;
        }
      } catch (_) {}
    }
    setState(() {
      crosshair = Offset(
        local.dx,
        bestY == null ? local.dy : box.maxHeight - (bestY - v.ymin) / v.dy * box.maxHeight,
      );
    });
    final yv = bestY ?? (v.ymax - local.dy / box.maxHeight * v.dy);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text('x = ${_fmtNum(x)}   y = ${_fmtNum(yv)}'),
    ));
  }

  void _scaleGraph(ScaleUpdateDetails d, BoxConstraints box) {
    if (_vpStart == null || _fpStart == null) return;
    setState(() {
      final w = box.maxWidth, h = box.maxHeight;
      // 围绕手势起点的焦点计算缩放（d.scale 是相对起点的累积缩放因子）
      final fx = _vpStart!.xmin + _fpStart!.dx / w * _vpStart!.dx;
      final fy = _vpStart!.ymax - _fpStart!.dy / h * _vpStart!.dy;
      final k = d.scale > 0 ? 1 / d.scale : 1;
      var nx1 = fx - (fx - _vpStart!.xmin) * k;
      var nx2 = fx + (_vpStart!.xmax - fx) * k;
      var ny1 = fy - (fy - _vpStart!.ymin) * k;
      var ny2 = fy + (_vpStart!.ymax - fy) * k;
      // 平移：内容跟随手指（与逐帧增量 focalPointDelta 语义一致，避免方向反置）
      final pdx = -(d.localFocalPoint.dx - _fpStart!.dx) / w * (nx2 - nx1);
      final pdy = (d.localFocalPoint.dy - _fpStart!.dy) / h * (ny2 - ny1);
      nx1 += pdx;
      nx2 += pdx;
      ny1 += pdy;
      ny2 += pdy;
      // 钳制：视口跨度限制在 [0.05, 1e5]
      if ((nx2 - nx1).abs() >= 0.05 && (nx2 - nx1).abs() <= 1e5 &&
          (ny2 - ny1).abs() >= 0.05 && (ny2 - ny1).abs() <= 1e5) {
        vp = Viewport(nx1, nx2, ny1, ny2);
      }
    });
  }

  /// 积分面积着色：选择函数与上下限，实时显示积分值
  void _showIntegralShade() {
    final aCtrl = TextEditingController(text: (intA ?? 0).toString());
    final bCtrl = TextEditingController(text: (intB ?? 1).toString());
    var selFn = intFn.clamp(0, math.max(0, fns.length - 1)).toInt();
    String? valueText;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (ctx, setSt) {
        void recompute() {
          final a = double.tryParse(aCtrl.text.trim());
          final b = double.tryParse(bCtrl.text.trim());
          if (a == null || b == null || selFn >= fns.length) {
            setSt(() => valueText = null);
            return;
          }
          try {
            final src = fns[selFn].kind == 'implicit'
                ? implicitEqSrc(fns[selFn].expr)
                : fns[selFn].expr;
            final v = integrate((t) => evaluate(src, t, paramValues, _angleMode, ans), a, b);
            setSt(() => valueText = _fmtNum(v));
          } catch (e) {
            setSt(() => valueText = '无法计算');
          }
        }

        return AlertDialog(
          title: const Text('积分面积着色'),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: selFn,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '函数', border: OutlineInputBorder()),
                items: [
                  for (int i = 0; i < fns.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        fns[i].expr.isEmpty ? '(空函数 ${i + 1})' : fns[i].expr,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: fns.isEmpty
                    ? null
                    : (v) {
                        setSt(() => selFn = v ?? 0);
                        recompute();
                      },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: aCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration:
                        const InputDecoration(labelText: '下限 a', border: OutlineInputBorder()),
                    onChanged: (_) => recompute(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: bCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration:
                        const InputDecoration(labelText: '上限 b', border: OutlineInputBorder()),
                    onChanged: (_) => recompute(),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueText == null ? '∫ f(x) dx = —' : '∫ f(x) dx = $valueText',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  intA = null;
                  intB = null;
                });
              },
              child: const Text('清除'),
            ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final a = double.tryParse(aCtrl.text.trim());
                final b = double.tryParse(bCtrl.text.trim());
                Navigator.of(ctx).pop();
                if (a == null || b == null) return;
                setState(() {
                  intA = math.min(a, b);
                  intB = math.max(a, b);
                  intFn = selFn;
                });
              },
              child: const Text('应用'),
            ),
          ],
        );
      }),
    );
  }

  // ================= 数据拟合页 =================

  /// 解析输入文本并做拟合（解析/拟合失败时给出明确提示）
  void _parseAndFit() {
    final pts = parseData(dataCtrl.text);
    String err = '';
    FitResult? res;
    if (pts.length < 2) {
      err = pts.isEmpty ? '未识别到数据，请用「x y」或「x, y」每行一组' : '至少需要 2 组数据';
    } else {
      res = fitData(pts, fitKind);
      if (res == null) {
        err = fitKind == 'exp' || fitKind == 'power'
            ? '指数 / 幂拟合要求 y > 0'
            : (fitKind == 'log' ? '对数拟合要求 x > 0' : '数据量不足或无法拟合该模型');
      }
    }
    setState(() {
      _pts = pts;
      _fit = res;
      dataError = err;
    });
  }

  void _setFitKind(String k) {
    setState(() => fitKind = k);
    _parseAndFit();
    _schedulePersist();
  }

  /// 把拟合曲线送到图形页（作为新函数追加）
  void _sendFitToGraph() {
    final fit = _fit;
    if (fit == null) return;
    setState(() {
      mode = 1;
      _addFn(fit.expr, 'y');
    });
    _schedulePersist();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(duration: Duration(seconds: 2), content: Text('已加入图形页函数列表')),
    );
  }

  Widget _dataPage() {
    final scheme = Theme.of(context).colorScheme;
    final pts = _pts ?? const <Pt>[];
    final fit = _fit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('数据（每行一组 x y，支持空格 / 逗号 / 制表符分隔）',
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 130,
            child: TextField(
              controller: dataCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '1 2.1\n2 4.05\n3 5.9\n4 8.2',
                isDense: true,
                contentPadding: EdgeInsets.all(8),
              ),
              onChanged: (_) => _parseAndFit(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final k in const [
                ['linear', '线性'],
                ['poly2', '二次'],
                ['poly3', '三次'],
                ['exp', '指数'],
                ['log', '对数'],
                ['power', '幂'],
              ])
                ChoiceChip(
                  label: Text(k[1], style: const TextStyle(fontSize: 12)),
                  selected: fitKind == k[0],
                  onSelected: (_) => _setFitKind(k[0]),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (dataError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('⚠ $dataError',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFD7263D))),
            ),
          if (fit != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${fit.name}拟合：${fit.equation}',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: scheme.primary)),
                  const SizedBox(height: 3),
                  Text('R² = ${fit.r2.toStringAsFixed(6)}    n = ${fit.n}    '
                      'r = ${pearsonR(pts).toStringAsFixed(6)}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.75))),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: pts.isEmpty
                  ? Center(
                      child: Text('输入数据后显示散点图与拟合曲线',
                          style: TextStyle(fontSize: 12, color: scheme.outline)))
                  : CustomPaint(
                      painter: _ScatterPainter(pts, fit, gridColor: scheme.outline.withOpacity(0.25),
                          axisColor: scheme.outline, labelColor: scheme.outline),
                      size: Size.infinite,
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: fit == null ? null : _sendFitToGraph,
                icon: const Icon(Icons.show_chart, size: 18),
                label: const Text('送到图形页', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: () {
                  dataCtrl.clear();
                  _parseAndFit();
                  _schedulePersist();
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('清空', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= 历史面板 =================
  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                const Text('计算历史', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_history.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() => _history.clear());
                      _schedulePersist();
                      Navigator.pop(c);
                    },
                    child: const Text('清空'),
                  ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(c)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _history.isEmpty
                  ? const Center(child: Text('暂无记录', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      controller: scroll,
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final h = _history[i];
                        final text = '${h.expr} = ${h.result}';
                        return ListTile(
                          title: Text(text, style: const TextStyle(fontSize: 15)),
                          onTap: () {
                            calcCtrl.text = h.expr;
                            Navigator.pop(c);
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: '复制',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(duration: Duration(seconds: 1), content: Text('已复制')),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 外壳 =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(mode == 0 ? '科学计算器' : (mode == 1 ? '图形计算器' : '数据拟合')),
        elevation: 0.5,
        actions: [
          if (mode == 0)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '计算历史',
              onPressed: _showHistory,
            ),
          TextButton(
            onPressed: () => setState(() => deg = !deg),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.22),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              minimumSize: const Size(58, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(
              deg ? 'DEG' : 'RAD',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
            ),
          ),
          IconButton(
            icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            tooltip: '切换浅/深色',
            onPressed: widget.onToggleDark,
          ),
          if (mode == 1) ...[
            IconButton(
              key: const Key('annoToggle'),
              icon: Icon(showAnno ? Icons.label_important : Icons.label_outline),
              tooltip: showAnno ? '关闭读值标注' : '标注零点 / 极值 / 交点',
              onPressed: () => setState(() => showAnno = !showAnno),
            ),
            IconButton(
              key: const Key('integralShade'),
              icon: const Icon(Icons.waterfall_chart),
              tooltip: '积分面积着色',
              onPressed: _showIntegralShade,
            ),
            IconButton(
              icon: const Icon(Icons.filter_center_focus),
              tooltip: '复位视图（双击绘图区也可）',
              onPressed: () => setState(() => vp = Viewport(-6.5, 6.5, -4.2, 4.2)),
            ),
          ],
        ],
      ),
      body: mode == 0 ? _calcPage() : (mode == 1 ? _graphPage() : _dataPage()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: mode,
        onDestinationSelected: (i) => setState(() => mode = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate), label: '计算器'),
          NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: '图形'),
          NavigationDestination(icon: Icon(Icons.scatter_plot_outlined), selectedIcon: Icon(Icons.scatter_plot), label: '数据'),
        ],
      ),
    );
  }
}
