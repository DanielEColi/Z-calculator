
## 构建环境（Z-calculator / Flutter）
- JDK17: D:/SW/Java/jdk-17.0.2；Android SDK: D:/Android/AndroidSDK；Flutter SDK: D:/Android/flutterSDK（3.27.1 stable）
- Gradle 下载须走代理：export GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=59442 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=59442"（沙箱代理端口随会话变化，用 env | grep -i proxy 查当前值）
- 项目 android/build.gradle 已配阿里云 maven 镜像；gradle-wrapper.properties 指向腾讯镜像
- GitHub API 操作：可用 `git credential fill`（host=github.com）取缓存 token，勿打印
- 发版约定见 app/README.md 版本规范：SemVer + versionCode 递增 + APK 命名 graph_calc_v<ver>.apk
