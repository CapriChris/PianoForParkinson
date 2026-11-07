# 琴伴 0.1.65+66：本机整合构建与验证

日期：2026-11-07。基于 App main `4a5197c`、Web main `20761b9` 整合，未推送 GitHub，未再次部署服务器，未安装真机。

- Flutter 全量测试：786 通过，2 个 opt-in 联调默认跳过。
- 单独启用真实本机 HTTPS 账号联调：1 通过，独立临时后端及数据库；覆盖两账号隔离、跨患者拒绝、计划进度 1/2→2/2、幂等上传、恢复、退出撤销和密码流程。
- Flutter 静态分析：No issues found。
- 原生迁移 JVM 文件/密文回归：通过。
- 本机 Web 账号、迁移、schema 测试：24 通过。
- 线上只读检查：健康接口 HTTP 200，未登录的 `/mobile/auth/me` HTTP 401。未写入生产患者或训练数据。
- Release 构建通过；正式包名 `com.pianoforparkinson.piano_practice`，版本 0.1.65，构建号 66；ARM64、ARMv7、x86_64 通用包，沿用本机开发签名。

APK：`D:/MyIdea/PianoForParkinson/releases/qinban-0.1.65-android-universal.apk`，666,480,735 字节。

```text
bcee0e7c1265a44d093caf21e8d0b9e1fec23679eb058a1e0a91e15e0850913d  qinban-0.1.65-android-universal.apk
```

构建命令：

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

日志：App `build/merge-20261107-tests.log`、`build/merge-20261107-analyze.log`、`build/merge-20261107-native.log`、`build/merge-20261107-https.log`、`build/merge-20261107-release.log`；Web `artifacts/merge-20261107-accounts.log`。

[更新内容与真机验收](../docs/2026-11-07-0.1.65-更新与验收.md)。摄像头、Keystore 跨重启、实际后台调度及厂商省电仍待真机验证。
