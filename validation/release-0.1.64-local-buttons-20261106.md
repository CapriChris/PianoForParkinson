# 琴伴 0.1.64+65 构建与验证

2026-11-06 · 账号页面按钮反馈 · 本机验收包，未推送 GitHub 或部署服务器。

## 验证

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub test/accounts test/widgets/qin_press_test.dart --reporter compact`：29 项通过。
- 新增三页交互场景：按住按钮可见缩小，取消按压不提交；网络请求等待期间显示对应加载状态，禁用按钮并阻止重复提交；失败后保留输入、恢复重试。
- 原密码显隐、焦点与选择范围、表单校验、账号隔离、小屏大字号，以及系统减少动画回归通过。
- Release 主应用构建通过，版本 `0.1.64`，构建号 `65`，与 `pubspec.yaml` 和应用内常量一致。
- 本次复用原按钮反馈组件，未修改后端接口；沿用 0.1.63 后端配套代码。
- 未进行本版真机安装验收。

## 安装包

文件 `qinban-0.1.64-android-universal.apk`，666,464,351 字节（635.59 MiB）。包名 `com.pianoforparkinson.piano_practice`；ARM64、ARMv7 和 x86_64 通用包，沿用既有开发签名。

安装包和校验文件位于 `D:/MyIdea/PianoForParkinson/releases/`，旧产物保留。

```text
a92d4b570201f265816936af41f9d733a560c48bc2906e3aab90bebb9d73e0d4  qinban-0.1.64-android-universal.apk
```

构建命令：

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

日志：`build/account-feedback-tests.log`、`build/account-feedback-analyze.log`、`build/account-feedback-release.log`。

[更新说明](../docs/2026-11-06-0.1.64-更新说明.md)
