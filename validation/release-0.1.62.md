# 琴伴 0.1.62+63 构建与验证

2026-11-06 · 登录与注册界面调整 · 本机验收包，未发布 GitHub 或部署服务端。

## 验证

- `flutter analyze --no-pub`：通过，无问题。
- 账号页面回归：8 项通过。覆盖未登录锁定、登录退出路由、会话恢复与过期、表单校验、密码眼睛随焦点显示和明密文状态、光标选择与焦点保持、确认密码独立控制、昵称字符计数与输入框内位置、移除勾选后可注册、找回密码页文案。
- 单独运行小屏布局预览：1 项通过，导出 390×844 的登录、密码聚焦、注册和找回密码布局并检查。预览使用本机字体，仅用于检查布局；未进行本版真机截图验收。
- Release 主应用构建通过。包名与既有主包相同，版本 `0.1.62`，Android 构建号 `63`。
- 注册仍发送兼容的 `sync_consent_version=account-sync-v1`；原后端接口和 0.1.61 后端交接包无需更换。AI 训练记录访问和视频授权逻辑沿用原实现。

## 产物

`qinban-0.1.62-android-universal.apk`，664,017,012 字节（633.26 MiB）。

本机目录 `D:/MyIdea/PianoForParkinson/releases/`，附 `SHA256SUMS-0.1.62.txt`。保留旧版安装包。

```text
97285a34267c53287fab466cc2b39b3516069865e0f2f279e13cbb7864a73c28  qinban-0.1.62-android-universal.apk
```

构建命令：

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

日志与预览位于 `build/account-layout-analyze.log`、`build/account-layout-tests.log`、`build/account-layout-previews.log`、`build/account-layout-previews/` 和 `build/account-layout-release-build.log`，不提交本机缓存。

[本版更新说明](../docs/2026-11-06-0.1.62-更新说明.md) · [账号与同步交接](../docs/2026-11-06-账号注册登录与自动同步交接.md)
