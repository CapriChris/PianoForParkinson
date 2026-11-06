# 琴伴 0.1.63+64 构建与验证

2026-11-06 · 发布前构建与验证记录。交付标签 `v0.1.63`；未部署公网服务器，未进行本版真机安装。

## 验证结果

- `flutter analyze --no-pub`：通过，无问题。
- 发布前完整 Flutter 套件：775 项通过、1 项跳过，无失败。
- 账号专项 22 项通过，覆盖注册/登录/重置、焦点与密码显隐、空值和长度提示、8/16 长度边界及 Unicode、会话与本地账号隔离、插画共用、去除钢琴符号、小屏横屏及大字号滚动。
- Web 认证、跨端权限、同步与数据库迁移相关回归共 51 项通过。新注册、重置和修改密码执行 8–16 位规则，旧账号较长密码仍可登录。
- 390×844 布局预览检查登录、注册和重置页，三页共用插画且位于文案下层。预览使用本机字体，仅用于布局核对，不替代 Android 真机验收。
- 已核对五档启动图标尺寸。`aapt dump badging` 确认应用使用新的自适应图标；`dump xmltree` 和 `dump resources` 确认背景色及前景资源引用。Release 打包会缩短资源文件名，按资源表验证，不依赖 ZIP 内原文件名。
- `apksigner verify --print-certs` 通过，证书 SHA-256 为 `69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca`。
- APK 中的共用插画与用户提供的 PNG 哈希一致。Release 构建成功。

## 产物

文件 `qinban-0.1.63-android-universal.apk`，666,464,351 字节（635.59 MiB）。包名 `com.pianoforparkinson.piano_practice`，versionName `0.1.63`、versionCode `64`，支持 ARM64、ARMv7 和 x86_64，最低 API 24。

本机目录为 `D:/MyIdea/PianoForParkinson/releases/`，提供 `SHA256SUMS-0.1.63.txt`，保留旧版产物。

```text
1100f803a574d18c9c7a0f1f8b3207d7991ce4a44065f1d456e22fc411b277be  qinban-0.1.63-android-universal.apk
fbf179b47780da829d90b0dbed5dd2ee057c780249910682251c1f5abf4e8a45  web-mobile-accounts-0.1.63-handoff.zip
```

## 构建和资源

```powershell
python tools/generate_launcher_icons.py
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

图标源 `assets/icon/icon.png`；顶部插画 `assets/images/42-auth-shared-header.png`。图标脚本只生成平台密度与安全区尺寸，不改动原图内容。通知栏沿用单色图标。

## 后端交付

新版交接包包含基于 Web `7e1c731` 的完整配套变更、文档及文件哈希清单。服务器需合并密码规则后重启。已经部署账号功能的环境无需新增迁移，从旧版首次部署仍需执行原 `n0c2d4e6f8a0` 迁移。本轮没有执行公网部署或真机端到端联调。

日志：`build/account-artwork-analyze.log`、`build/account-artwork-tests.log`、`build/account-artwork-previews.log`、`build/account-artwork-release.log`；Web 日志为 `artifacts/account-artwork-regression.log`。

[更新说明](../docs/2026-11-06-0.1.63-更新说明.md) · [账号与部署交接](../docs/2026-11-06-账号注册登录与自动同步交接.md)

发布前完整套件日志：`build/release-0.1.63-final-tests.log`。

配套 Web 提交：`f06a85a4aa09978a14579664c9e0b88415f5c4b7`；[草稿合并请求 #1](https://github.com/WuChangqing1/PD-Rehab-Web/pull/1)。后端交接包与此提交的 13 个文件一致，完整提交号和逐文件哈希记录在包内 `MANIFEST.json`。
