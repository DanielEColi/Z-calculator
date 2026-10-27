# 构建指南

## 环境要求

- Flutter 3.x（稳定版）
- **JDK 17**（必须：Gradle 7.4 在更高/更低版本 JDK 下无法编译新版插件 build.gradle）
- Android SDK

## 构建步骤

```bash
cd app
export JAVA_HOME=/opt/jdk17            # Windows 示例：D:/SW/Java/jdk-17.0.2
export ANDROID_SDK_ROOT=/opt/android-sdk
flutter pub get
flutter analyze          # 期望 0 error
flutter test             # 期望全部通过
flutter build apk --release
```

产物：`app/build/app/outputs/flutter-apk/app-release.apk`

## 命名规范

`graph_calc_v<MAJOR>.<MINOR>.<PATCH>.apk`，例如 `graph_calc_v0.3.0.apk`。每次发版重新构建，不覆盖旧版本文件。
