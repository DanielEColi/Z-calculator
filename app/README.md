# sci_graph_calc



## 概览 / Overview

"Scientific & Graphing Calculator" is a cross-platform, offline Flutter app for iOS 15+ and Android 8.0+, requiring no login, no network access, and containing no ads. It combines two core capabilities — scientific calculation and function graphing. The calculator delivers real-time evaluation, basic arithmetic, trigonometric and logarithmic functions, square roots, π/e, and a one-tap DEG/RAD toggle, with an auto-saved history that can be viewed, copied, and cleared. The graph page offers a Desmos-style experience: instant plotting of multiple functions, live parameter sliders, adaptive 1-2-5 axis ticks with accurate discontinuity handling, and a draggable divider to resize the input and plotting panes. Designed with native iOS aesthetics — circular keys, orange action buttons, and smooth press animations — it makes even complex math feel effortless and elegant.

「科学计算器 + 图形计算器」是一款基于 Flutter 开发的跨平台离线应用，支持 iOS 15+ 与 Android 8.0+，无需登录、不联网、无广告。它集成了科学计算与函数绘图两大核心能力：计算器支持实时计算、四则运算、三角函数、对数、开方、π/e 等科学函数，并可在 DEG/RAD 角度模式间一键切换，计算历史可自动记录并查看、复制与清空；图形页采用类 Desmos 的交互，支持多函数即时绘制、参数滑块实时调形、自适应坐标刻度与精确的不连续点断笔，并可拖拽分隔条自由调节输入区与绘图区比例。整体以 iOS 原生美学打造，圆形按键、橙色操作键与流畅的按压动效，让复杂运算也能轻松优雅地完成。

一款基于 Flutter 开发的**离线**双模式计算器，无需登录、无广告，支持 iOS 15+ / Android 8.0+。设计参考 Desmos 与 iOS 原生风格，核心覆盖**科学计算**与**函数绘图**两大场景。

------

## 一、科学计算 / Scientific Calculator



| 能力     | 说明 (中文)                              | Description (EN)                            |
| :------- | :--------------------------------------- | :------------------------------------------ |
| 实时计算 | 输入即出结果，无需按 `=`                 | Live evaluation as you type — no `=` needed |
| 基础运算 | `+ − × ÷`、括号、`ans`(上一次结果)       | `+ − × ÷`, parentheses, `ans` variable      |
| 科学函数 | `sin / cos / tan / ln / √ / x² / π / e`  | `sin / cos / tan / ln / √ / x² / π / e`     |
| 角度模式 | `DEG` / `RAD` 一键切换（白底药丸按钮）   | `DEG` / `RAD` toggle (white pill button)    |
| 计算历史 | 自动记录（`=` 触发），可查看、复制、清空 | Auto history on `=`; view / copy / clear    |

> 说明：历史记录为**会话级**保存（关闭重开清空），后续可扩展为本地持久化。

------

## 二、图形计算 / Graphing



| 能力       | 说明 (中文)                                  | Description (EN)                                     |
| :--------- | :------------------------------------------- | :--------------------------------------------------- |
| 函数列表   | 多函数输入，即时绘制，类 Desmos              | Function list with instant plotting (Desmos-like)    |
| 参数滑块   | 支持带参函数，拖拽滑块实时变化曲线           | Parameter sliders — drag to reshape curves live      |
| 智能坐标   | 自适应 1-2-5 刻度；不连续点自动断笔          | Adaptive 1-2-5 ticks; auto pen-up at discontinuities |
| 负区间修复 | 正确绘制 `x²` 等负 x 部分曲线                | Correctly plots negative-x curves (e.g. `x^2`)       |
| 符号工具栏 | 图形页可直接输入 `√ / π / x² / ^` 等         | Symbol bar for `√ / π / x² / ^` on graph page        |
| 区域调节   | 拖拽分隔条调整输入区/绘图区比例（0.25–0.55） | Drag divider to resize input/graph panes             |

------

## 三、交互与美学 / UX & Aesthetics

- **iOS 风格**：圆形按键、橙色操作键（`#FF9F0A`）、按压动效，`=` 键加宽更醒目
- **分隔条约定**：向下拖 → 输入区变大；向上拖 → 图形区变大
- **零权限、纯离线**：不联网、不收集数据、无广告
