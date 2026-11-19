# 琴伴 Android 完整安装包更新

琴伴在登录页或主界面联网检查新版。「设置 → 关于本版本 → 检查更新」也可主动检查。发现新版时显示版本、更新内容和安装包大小。用户选择下载后，可查看进度、取消或重试。校验通过后点击「安装更新」，由 Android 确认覆盖安装，安装完成后打开琴伴。首次使用该安装来源可能需要授权。

## 给 Web 与发布流程的约定

正式渠道默认读取公开静态文件 `https://ccqspace.site/pd-rehab/assets/app-releases/latest-android.json`。可通过 `--dart-define=PD_ANDROID_UPDATE_MANIFEST=...` 为联调包指定独立的 HTTPS 清单。Web 登录页的 APK 下载入口可以读取正式清单的 `apkUrl`，与 App 共用发布指针。

```json
{
  "schemaVersion": 1,
  "packageName": "com.pianoforparkinson.piano_practice",
  "versionName": "0.1.74",
  "versionCode": 75,
  "apkUrl": "https://ccqspace.site/pd-rehab/assets/app-releases/0.1.74/qinban-0.1.74-android-universal.apk",
  "sizeBytes": 102723070,
  "sha256": "<替换为最终已签名 APK 的 64 位十六进制 SHA-256>",
  "notesZh": "替换为本次更新内容",
  "notesEn": "Replace with the release notes"
}
```

上面是格式示例。发布时先上传最终签名的通用 APK，核对下载内容、字节数与摘要，再发布清单。APK 和清单须为同源 HTTPS 请求且直接返回文件，两者均不跟随重定向。清单建议使用短缓存或 `Cache-Control: no-cache`。清单未发布时返回 404，App 正常使用。新版的 `versionCode` 应高于已安装版本，发布包须沿用同一包名、同一签名。`.validation` 等独立包使用各自的清单及安装包。

## 合并与验收

- 与 Shorebird 共存时，Dart 补丁仍针对其基线版本。需要改变安装包时，把含更新器的 App 分支与 Shorebird 分支合并，用最终渠道的发布方式构建完整新版。SHA-256、大小和清单都应取自最终签名的实际产物。
- 已安装普通旧版的用户需要先手动覆盖安装一次包含更新器的版本。后续发布的 APK 可使用应用内流程。系统可能结束旧版进程，安装器的「打开」按钮或桌面入口可启动新版。
- 下载落在 App 私有缓存；通过 SHA-256、文件大小、包名、构建号和签名校验后，系统安装器才得到 APK 的临时读取权限。不会提前卸载现有版本。
- 联调时准备两个同包名、同签名的独立测试版本。低构建号包启用测试清单，清单指向高构建号包。验证稍后、取消、断网、安装权限、手工取消安装后重试、覆盖成功后本机记录保留。另验证错误指纹、同构建号和不同包名被拒绝。

开发验证使用隔离测试包 `com.pianoforparkinson.piano_practice.dance_flow_test` 和本机 HTTPS 服务，从构建号 73 覆盖到 74。已验证新版提示、完整下载、安装授权、取消安装后重试、系统确认覆盖、打开新版，以及应用私有目录中的测试文件在覆盖后仍存在。41 项相关 Flutter 测试通过，静态分析通过。生产清单及正式安装包由合并后的发布流程生成。
