# 琴伴 0.1.66+67 构建与验证

日期：2026-11-07。基于 App main `4a5197c` 的本机整合代码；GitHub 发布标签 `v0.1.66`。本轮不修改后端、不执行生产部署，也未安装真机验收。

## 更新

设置页账号入口顺序、首次引导退出入口、账号页及弹窗按压反馈；训练临时失活与实际中断分离、通知降音量恢复、舞蹈暂停与手动恢复、录像跟随暂停、曲目三拍视觉准备。详见 [更新说明](../docs/2026-11-07-0.1.66-更新说明.md)。

## 本轮验证

- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub --reporter expanded`：**804 通过、2 个 opt-in 联调默认跳过、0 失败**。两项独立联调本轮未再次执行，既往账号联调记录见 0.1.65 验证报告。
- Release 通用 APK 构建通过，包括更新后的 Android Kotlin 与三种 ABI 原生音频代码；包名 `com.pianoforparkinson.piano_practice`，versionName `0.1.66`，versionCode `67`。
- ARM64、ARMv7、x86_64；最低 API 24，目标 API 36。包名及签名与本机既有正式应用保持一致，可覆盖同包名及同签名旧版。
- APK 签名验证通过。签名证书 SHA-256：`69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca`，沿用内部测试开发签名。
- 安装包复制到版本目录后再次计算 SHA-256，与原始构建产物一致。
- Vivo 真机通知/通知栏/来电、耳机路由切换、锁屏、录像与恢复仍待设备验收。未将自动化测试结果视为已完成厂商系统行为验证。

## 安装包

`D:/MyIdea/PianoForParkinson/releases/qinban-0.1.66-android-universal.apk`，666,497,091 字节，约 635.62 MiB。

```text
ab600f1c85f26f96431ebf63ad5b9cc7f30c4953e6b04bc4b15d0fb51b734937  qinban-0.1.66-android-universal.apk
```

[GitHub Release](https://github.com/CapriChris/PianoForParkinson/releases/tag/v0.1.66) · [APK 下载](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.66/qinban-0.1.66-android-universal.apk) · [校验文件](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.66/SHA256SUMS-0.1.66.txt)

## 构建参数

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

默认账号 API：`https://ccqspace.site/pd-rehab/api`；保留 `PD_API_BASE` 覆盖入口。AI 网关沿用现有阿里云服务，不含密钥。

本机日志：`build/release-0.1.66-tests.log`、`build/release-0.1.66-analyze.log`、`build/release-0.1.66-build.log`；上传后的附件大小和摘要由发布脚本与 GitHub API 返回值逐项核对。
