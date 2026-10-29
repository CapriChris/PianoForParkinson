# 琴伴 0.1.52+53 构建验证

日期：2026-10-28。应用包名 `com.pianoforparkinson.piano_practice`，内部演示 APK 使用项目现有 Android Debug 签名，不适用于正式发布。

- Flutter 静态分析：通过，[日志](build-0.1.52-analyze.log)。
- 相关界面、字号、音符、乐谱、趋势与曲谱数据测试：59 项通过，[日志](build-0.1.52-tests.log)。
- 位置与图形试玩布局测试：4 项通过，[日志](build-0.1.52-switch-tests.log)。
- `flutter build apk --release`：通过，[最终日志](build-0.1.52-release-final.log)。前两次 `--no-pub` 构建因旧的集成测试插件注册文件未刷新而失败；完整 Flutter 构建流程完成依赖解析及发布插件配置后成功。失败日志保留在同目录。
- APK 元数据：versionName `0.1.52`、versionCode `53`、minSdk `24`、targetSdk `36`；签名验证通过，证书为 Android Debug。
- 交付文件：[琴伴-0.1.52-internal.apk](../../releases/琴伴-0.1.52-internal.apk)，87,306,369 字节，SHA-256 `4287AF0C60CA8B6AC10F7329C27FDC8E40C7C275336A6EE1A72E4F2C37B26ADA`，与 Flutter 构建输出一致。

本次未运行完整测试套件，未安装到模拟器或手机，未进行真实设备视觉、交互或听音验收。之前发现的部分旧页面测试仍以旧文字按钮或导航为断言，不计入本次通过数。
