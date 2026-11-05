# 琴伴 0.1.60+61 构建与验证

2026-11-05 · Android 内部测试版 · Git 标签 `v0.1.60`

## 版本与产物

- `pubspec.yaml` 为 `0.1.60+61`；应用内显示和记录环境中的版本同步为 `0.1.60`，构建号同步为 `61`。
- 主应用包名 `com.pianoforparkinson.piano_practice`，通用 Release 包，不使用独立测试包名。
- 安装包名 `qinban-0.1.60-android-universal.apk`；本机副本位于 `D:/MyIdea/PianoForParkinson/releases/`。
- 沿用现有开发签名，用于团队内部测试。相同签名的主应用可覆盖安装；本轮没有卸载、安装或清空手机数据。
- 产物大小 663,536,107 字节（632.80 MiB）。最低 Android API 24，目标 API 36；包含 ARM64、ARMv7 和 x86_64。
- `apksigner verify --verbose --print-certs` 通过，签名证书 SHA-256 为 `69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca`，与此前主应用开发签名一致。
- 包内四段舞蹈视频的大小和 SHA-256 均与 `assets/video/manifest.json` 匹配。
- APK SHA-256：

```text
87d41e06bb1faf0b92d1cd1228d14ba248cef00ca30d2f73eed58135e2fbc876  qinban-0.1.60-android-universal.apk
```

同目录提供 `SHA256SUMS-0.1.60.txt`，与 APK 一同发布到 GitHub Release。源码提交到 `main`，发布标签为 `v0.1.60`；安装包和本机构建缓存不写入 Git 源码历史。

## 构建参数

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

启用云端服务联调。Web API 地址在 App 中填写 `https://ccqspace.site/pd-rehab/api`，已有用户设置保留。AI 网关使用 HTTPS；APK 不包含模型服务密钥或测试账号密码。

首次带 `--no-pub` 构建失败：本机残留的插件注册文件引用了仅测试使用的 `integration_test`，正式版编译时该插件不可用。改用上述完整构建命令，按 Release 模式重新生成插件注册文件后重试；没有修改业务代码或 SDK 源码。

## 自动化验证

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub --reporter compact`：752 项通过，1 项跳过，无失败。
- `python -m unittest discover -s test/tools -p '*_test.py'`：2 项通过。
- 新增回归覆盖退出弹窗的保存、不保存、取消和失败重试；真实 SQLite 校验丢弃暂存记录、恢复既有或空的难度状态、删除失败时事务回滚，以及拒绝丢弃已保存记录。
- 其他测试覆盖历史会话持久化、档案隔离、同一会话上下文及更多证据和历史轮次的网关请求。

本机日志位于 `build/release-0.1.60-analyze.log`、`build/release-0.1.60-tests.log`、`build/release-0.1.60-build.log` 和 `build/release-0.1.60-build-retry.log`，不提交构建缓存。

## 验收边界

本轮没有运行真机集成测试，也没有部署阿里云函数或修改 Web 服务。AI 实际额度受线上环境变量、全局额度及每 IP 额度共同约束。需要按 [联调交接与验收](../docs/Android双端联调交接与验收.md) 复测计划进度、真实接口和训练视频功能。

[本版更新说明](../docs/2026-11-05-0.1.60-更新说明.md) · [GitHub Release](https://github.com/CapriChris/PianoForParkinson/releases/tag/v0.1.60)
