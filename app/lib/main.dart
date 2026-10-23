import 'dart:math' as math;
import 'package:flutter/material.dart';

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
      title: '科学计算器',
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

const _functions = {
  'sin': 1, 'cos': 1, 'tan': 1, 'asin': 1, 'acos': 1, 'atan': 1,
  'ln': 1, 'log': 1, 'log2': 1, 'sqrt': 1, 'abs': 1, 'exp': 1,
};

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
      raw.add(_Tok('id', src.substring(i, j).toLowerCase()));
      i = j;
    } else if ('+-*/^'.contains(c)) {
      raw.add(_Tok('op', c));
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
  final out = <_Tok>[];
  for (final t in raw) {
    if (t.type == 'id') {
      final s = t.text;
      if (_functions.containsKey(s) || s == 'pi' || s == 'e' || s == 'ans') {
        out.add(t);
      } else if (s.length == 1) {
        out.add(t);
      } else {
        int k = 0;
        while (k < s.length) {
          int best = 0;
          for (final f in _functions.keys) {
            if (s.startsWith(f, k)) {
              best = f.length;
              out.add(_Tok('id', f));
              break;
            }
          }
          if (best == 0) {
            if (s.startsWith('pi', k)) {
              out.add(_Tok('id', 'pi'));
              best = 2;
            } else {
              out.add(_Tok('id', s[k]));
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
          (prev.type == 'id' && !_functions.containsKey(prev.text));
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

/// 求值（x=0 时即普通计算）；抛出 [ExprError]
double evaluate(String src, double x, Map<String, double> params, AngleMode am, double ans) {
  if (src.trim().isEmpty) throw ExprError('表达式为空');
  final node = Parser(src).parse();
  final p = Map<String, double>.from(params);
  p['ans'] = ans;
  return node.eval(x, p, am);
}

/// 收集单字母参数（滑块）
Set<String> collectParams(String src) {
  final set = <String>{};
  try {
    for (final t in _tokenize(src)) {
      if (t.type == 'id' && !_functions.containsKey(t.text) &&
          t.text != 'pi' && t.text != 'e' && t.text != 'ans' && t.text != 'x') {
        set.add(t.text);
      }
    }
  } catch (_) {}
  return set;
}

// ============================ 绘图 ============================

class Viewport {
  double xmin, xmax, ymin, ymax;
  Viewport(this.xmin, this.xmax, this.ymin, this.ymax);
  double get dx => xmax - xmin;
  double get dy => ymax - ymin;
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

  GraphPainter(this.vp, this.fns, this.params, this.angleMode, this.ans, this.crosshair,
      {required this.gridColor, required this.axisColor, required this.labelColor});

  @override
  void paint(Canvas canvas, Size size) {
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

    // 曲线：逐像素采样 + 断笔检测
    final n = math.max(64, size.width.toInt());
    for (final fn in fns) {
      if (!fn.visible || fn.expr.trim().isEmpty) continue;
      final paint = Paint()
        ..color = fn.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
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

    if (crosshair != null) {
      final p = Paint()..color = const Color(0x99FF5722)..strokeWidth = 1;
      canvas.drawLine(Offset(0, crosshair!.dy), Offset(size.width, crosshair!.dy), p);
      canvas.drawLine(Offset(crosshair!.dx, 0), Offset(crosshair!.dx, size.height), p);
      canvas.drawCircle(crosshair!, 4, Paint()..color = const Color(0xFFFF5722));
    }
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

class FnRow {
  String expr;
  Color color;
  bool visible;
  FnRow(this.expr, this.color, {this.visible = true});
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

  // —— 图形 ——
  final List<TextEditingController> fnCtrls = [];
  final List<FnRow> fns = [];
  final Map<String, double> paramValues = {};
  Viewport vp = Viewport(-6.5, 6.5, -4.2, 4.2);
  double inputFraction = 0.32;
  bool inputCollapsed = false;
  Offset? crosshair;

  @override
  void initState() {
    super.initState();
    _addFn('sin(x)');
    _addFn('a*x^2');
  }

  @override
  void dispose() {
    for (final c in fnCtrls) {
      c.dispose();
    }
    calcCtrl.dispose();
    super.dispose();
  }

  void _addFn([String expr = '']) {
    final c = TextEditingController(text: expr);
    c.addListener(_onFnChanged);
    fnCtrls.add(c);
    fns.add(FnRow(expr, fnPalette[fns.length % fnPalette.length]));
    _onFnChanged();
  }

  void _onFnChanged() {
    for (int i = 0; i < fnCtrls.length; i++) {
      fns[i].expr = fnCtrls[i].text;
    }
    final used = <String>{};
    for (final c in fnCtrls) {
      used.addAll(collectParams(c.text));
    }
    for (final k in used) {
      paramValues.putIfAbsent(k, () => 1);
    }
    paramValues.removeWhere((k, _) => !used.contains(k));
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

  void _equals() {
    try {
      final src = calcCtrl.text.trim();
      if (src.isEmpty) return;
      final r = evaluate(src, 0, {}, _angleMode, ans);
      ans = r;
      calcResult = _fmtNum(r);
    } on ExprError catch (e) {
      calcError = e.message;
    } catch (_) {
      calcError = '表达式错误';
    }
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

  // —— iOS 风格键盘：圆形键 / 橙色运算符 / 差异化尺寸 ——
  static const _opKeys = {'+', '−', '×', '÷', '=', '^'};
  static const _funcKeys = {
    'C', '⌫', 'ans', '(', ')', 'π', 'e', 'x', 'x!',
    'sin(', 'cos(', 'tan(', 'asin(', 'acos(', 'atan(', 'ln(', 'log(', '√(',
  };

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
            fontSize: isOp ? cell * 0.44 : (isFunc ? cell * 0.30 : cell * 0.42),
            fontWeight: isOp ? FontWeight.w500 : FontWeight.w400,
            onTap: () => _press(label),
          ),
        );
      }

      return Column(
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
      );
    });
  }

  Widget _calcPage() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // 显示区
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(children: [
                  Text('ans = ${_fmtNum(ans)}', style: TextStyle(fontSize: 12, color: scheme.outline)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => deg = !deg),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        deg ? 'DEG' : 'RAD',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                SizedBox(
                  height: 52,
                  child: TextField(
                    controller: calcCtrl,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w300),
                    keyboardType: TextInputType.none,
                    showCursor: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '0',
                    ),
                  ),
                ),
                if (calcResult.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      child: Text('= $calcResult',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: scheme.primary)),
                    ),
                  ),
                if (calcError.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('⚠ $calcError', style: const TextStyle(fontSize: 13, color: Color(0xFFD7263D))),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => sciPage = !sciPage),
                icon: Icon(sciPage ? Icons.calculate_outlined : Icons.functions, size: 18),
                label: Text(sciPage ? '基本键盘' : '科学键盘', style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        // 键盘区
        Expanded(flex: 8, child: _keypad()),
      ],
    );
  }

  // ================= 图形 =================
  Widget _graphPage() {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (ctx, outer) {
        final bodyH = outer.maxHeight;
        final inputH = bodyH * (inputCollapsed ? 0.07 : inputFraction);
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: inputH,
          child: Column(
            children: [
              Row(children: [
                IconButton(
                  icon: Icon(inputCollapsed ? Icons.expand_more : Icons.expand_less),
                  tooltip: inputCollapsed ? '展开输入区' : '折叠输入区',
                  onPressed: () => setState(() => inputCollapsed = !inputCollapsed),
                ),
                Text('函数列表', style: TextStyle(fontSize: 13, color: scheme.outline)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.add), tooltip: '新增函数', onPressed: () => _addFn()),
              ]),
              if (!inputCollapsed)
                Expanded(
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
                          Text('y =', style: TextStyle(fontSize: 14, color: scheme.outline)),
                          Expanded(
                            child: TextField(
                              controller: fnCtrls[i],
                              style: TextStyle(fontSize: 15, color: fn.color),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                hintText: '如 a*x^2 + 1',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() {
                              fnCtrls[i].dispose();
                              fnCtrls.removeAt(i);
                              fns.removeAt(i);
                            }),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
              if (!inputCollapsed)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final e in paramValues.entries)
                        Container(
                          width: 240,
                          margin: const EdgeInsets.only(right: 10),
                          child: Row(children: [
                            Text('${e.key} = ${e.value.toStringAsFixed(1)}',
                                style: const TextStyle(fontSize: 12)),
                            Expanded(
                              child: Slider(
                                min: -5,
                                max: 5,
                                divisions: 100,
                                value: e.value.clamp(-5.0, 5.0),
                                onChanged: (v) => setState(() => paramValues[e.key] = v),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 可拖动分隔条
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
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, box) {
              final isDark = Theme.of(ctx).brightness == Brightness.dark;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tapGraph(d.localPosition, box),
                onScaleStart: (_) => setState(() => crosshair = null),
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
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
  );
}

  void _tapGraph(Offset local, BoxConstraints box) {
    final x = vp.xmin + local.dx / box.maxWidth * vp.dx;
    double bestDist = double.infinity;
    double? bestY;
    for (final fn in fns) {
      if (!fn.visible || fn.expr.trim().isEmpty) continue;
      try {
        final y = evaluate(fn.expr, x, paramValues, _angleMode, ans);
        if (y.isNaN || y.isInfinite) continue;
        final py = box.maxHeight - (y - vp.ymin) / vp.dy * box.maxHeight;
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
        bestY == null ? local.dy : box.maxHeight - (bestY - vp.ymin) / vp.dy * box.maxHeight,
      );
    });
    final yv = bestY ?? (vp.ymax - local.dy / box.maxHeight * vp.dy);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text('x = ${_fmtNum(x)}   y = ${_fmtNum(yv)}'),
    ));
  }

  void _scaleGraph(ScaleUpdateDetails d, BoxConstraints box) {
    setState(() {
      final scale = d.scale;
      final fx = vp.xmin + d.localFocalPoint.dx / box.maxWidth * vp.dx;
      final fy = vp.ymax - d.localFocalPoint.dy / box.maxHeight * vp.dy;
      if (scale != 1 && scale > 0) {
        final k = 1 / scale;
        final nx1 = fx - (fx - vp.xmin) * k, nx2 = fx + (vp.xmax - fx) * k;
        final ny1 = fy - (fy - vp.ymin) * k, ny2 = fy + (vp.ymax - fy) * k;
        // 缩放钳制：视口跨度限制在 [0.05, 1e5]，防止误操作缩放到极端值
        if ((nx2 - nx1).abs() >= 0.05 && (nx2 - nx1).abs() <= 1e5 &&
            (ny2 - ny1).abs() >= 0.05 && (ny2 - ny1).abs() <= 1e5) {
          vp = Viewport(nx1, nx2, ny1, ny2);
        }
      }
      final pdx = -d.focalPointDelta.dx / box.maxWidth * vp.dx;
      final pdy = d.focalPointDelta.dy / box.maxHeight * vp.dy;
      final px1 = vp.xmin + pdx, px2 = vp.xmax + pdx;
      final py1 = vp.ymin + pdy, py2 = vp.ymax + pdy;
      if ((px2 - px1).abs() >= 0.05 && (px2 - px1).abs() <= 1e5 &&
          (py2 - py1).abs() >= 0.05 && (py2 - py1).abs() <= 1e5) {
        vp = Viewport(px1, px2, py1, py2);
      }
    });
  }

  // ================= 外壳 =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(mode == 0 ? '科学计算器' : '图形计算器'),
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: () => setState(() => deg = !deg),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.22),
              primary: Colors.white,
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
          if (mode == 1)
            IconButton(
              icon: const Icon(Icons.filter_center_focus),
              tooltip: '复位视图（双击绘图区也可）',
              onPressed: () => setState(() => vp = Viewport(-6.5, 6.5, -4.2, 4.2)),
            ),
        ],
      ),
      body: mode == 0 ? _calcPage() : _graphPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: mode,
        onDestinationSelected: (i) => setState(() => mode = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate), label: '计算器'),
          NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: '图形'),
        ],
      ),
    );
  }
}
