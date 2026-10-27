# 版本规范

> 强制约定，每次改动都必须遵守。

1. **语义化版本（SemVer 2.0.0）**：`MAJOR.MINOR.PATCH`
   - `MAJOR`：不兼容的界面 / 交互 / 数据格式变更
   - `MINOR`：向下兼容的新功能
   - `PATCH`：向下兼容的问题修复、样式微调
2. **序列起点为 `v0.1.0`**。`0.x.y` 表示初始开发阶段（允许破坏性调整）；稳定期发布 `v1.0.0`。
3. **`versionCode` 单调递增**（Android 覆盖安装的硬性要求），与 `versionName` 解耦：
   - `pubspec.yaml` 写 `version: <versionName>+<versionCode>`
   - 每次发版 `versionCode` +1，不允许回退或复用
4. **每次改动必须同步更新 app/README.md 的「变更历史」**（顶部追加：版本号、日期、变更类型、内容）。
5. **每次发版必须重新构建 APK**，按命名规范输出。

变更类型标记：`新增` / `修改` / `修复` / `移除`。
