# Z-calculator（科学计算器 + 图形计算器）

![License](https://img.shields.io/badge/license-GPL--3.0-blue)
![Version](https://img.shields.io/badge/version-v0.3.0-green)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B)

一套 Flutter 代码实现的**离线**计算器 App，包含「科学计算器」「图形计算器」「数据拟合」三个页面。表达式解析引擎、绘图引擎、界面均为自研，**无第三方数学库依赖**；不联网、不登录、无广告，APK 零权限（不申请网络 / 存储 / 通知）。

- 包名：`com.workbuddy.sci_graph_calc`
- 当前版本：**v0.3.0**（versionCode 15）
- 唯一依赖：`shared_preferences`（仅用于本地持久化）

## 功能特性

### 🧮 科学计算器

- **实时求值**：输入表达式即预览结果，无需按 `=`
- 四级信息层级（Google 双行式）：`ans` 元信息 → 历史灰字 → 当前表达式 → 结果大字
- **纸带历史**：按 `=` 提交入带并换行，历史面板可回填；整数结果联动显示 HEX / OCT / BIN（二进制按字节分组，点按复制）
- **双键盘**：科学键盘 / 基本键盘，按钮或左右滑动切换
- **内联微积分与方程求根**（可参与四则运算与嵌套）：
  - `integral(f, a, b)` 定积分——自适应 Simpson，自动绕开 `1/x`、`tan` 等极点
  - `diff(f, x0[, h])` 数值导数——中心差分
  - `solve(f, a, b)` 区间求零点——扫描定位 + 二分收敛
  - 工具栏「∫」按钮图形化生成上述表达式，不必记忆语法
- 多项式求根：Durand-Kerner 迭代求全部根（含复根）
- **持久化**：历史、纸带、`ans`、函数列表与参数值写入本地，重启自动恢复

### 📈 图形计算器

- 显式函数 `y = f(x)` 与隐式方程 `F(x, y) = 0`（等值线绘制），一键切换并自动改写表达式
- **参数自动提取**：表达式中出现的字母自动生成滑块，区分大小写；拖到边缘自动翻倍扩展范围，点按数值可精确输入
- 等比例视口（圆不画成椭圆）、滚轮 / 双指缩放、拖动平移、双击复位
- 自适应刻度、断笔检测（处理 `1/x`、`tan` 等不连续点）
- **读值标注**：自动标注零点、极大 / 极小、两函数交点，坐标由 `solveRoot` + 数值导数精确收敛（非采样插值近似）
- **积分面积着色**：选择函数与上下限，填充 ∫ 区域并实时显示积分值
- 宽屏（横屏 / 平板）自动分栏：左侧常驻输入区，右侧绘图区

### 📊 数据拟合

- 数据输入：每行一组 `x y`，支持空格 / 半角逗号 / 中文逗号 / 制表符分隔，忽略空行与 `#` 注释
- 拟合模型：线性、二次、三次多项式、指数、对数、幂（后三者自动做对数变换后最小二乘）
- 指标：方程文本、`R²`、`n`、皮尔逊相关系数 `r`
- 散点图 + 蓝色拟合曲线，一键「送到图形页」追加为函数
- 数据与拟合类型同样持久化

## 下载

前往 [**Releases**](https://github.com/DanielEColi/Z-calculator/releases) 下载最新 APK，命名规范为 `graph_calc_v<版本>.apk`（如 `graph_calc_v0.3.0.apk`）。

## 从源码构建

```bash
cd app
# 需要 JDK 17（Gradle 7.4 在更高 / 更低版本 JDK 下无法编译）
export JAVA_HOME=/opt/jdk17          # 按实际路径修改
export ANDROID_SDK_ROOT=/opt/android-sdk
flutter pub get
flutter analyze          # 期望 0 error
flutter test             # 期望全部通过
flutter build apk --release
```

产物：`app/build/app/outputs/flutter-apk/app-release.apk`

更多细节见 [app/README.md](app/README.md)。

## 版本规范

语义化版本（SemVer 2.0.0），`versionCode` 单调递增，每次发版重新构建 APK。完整规范与逐版本变更历史见 [app/README.md · 变更历史](app/README.md#变更历史)。

## 目录结构

```
.
├── app/                  Flutter 工程
│   ├── lib/main.dart     全部源码（表达式引擎、绘图器、三页面 UI）
│   ├── test/             单元测试与 Widget 测试
│   ├── android/          Android 工程配置
│   └── pubspec.yaml      版本号在此维护
├── LICENSE               GNU GPL v3
└── README.md
```

## 许可证

本项目以 [**GNU GPL v3**](LICENSE) 发布：任何人可自由使用、修改与再分发，但基于本项目的派生作品必须以相同协议开源共享。
