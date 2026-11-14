# 琴伴 0.1.72+73 构建与验证

日期：2026-11-14。基于上一公开版本0.1.70后的本机提醒修复与界面优化发布，标签 `v0.1.72`。本次不修改Web后端、不部署服务器、不安装到真机。

## 更新与验证

- 通知图标保留修复；通用提醒设置及机型路由；自启动、后台活动独立“去开启”；提示卡临时/永久关闭；紧凑圆形图标按钮；等宽横排确认按钮。详见 [更新说明](../docs/2026-11-14-0.1.72-更新说明.md)。
- 升级版本常量后运行相关Flutter测试：**155项通过、0失败**。覆盖图标圆形可见尺寸和透明点击区域、弹窗横排等宽等高与边框、小屏/横屏/中英文/大字体、提醒权限状态机、提示偏好、计划编辑、账号、AI对话、语音、钢琴退出与舞蹈流程。本次不重跑全量测试。日志 `build/release-0.1.72-tests.log`。
- `flutter analyze --no-pub`：No issues found。日志 `build/release-0.1.72-analyze.log`。
- 通用release构建成功（Gradle 69.1秒），构建参数见下方，日志 `build/release-0.1.72-build.log`。包含Android原生提醒设置桥接，必须完整更新安装，不能仅热重载。
- 实际APK确认versionName为0.1.72、versionCode为73；签名校验通过，与0.1.70/0.1.71使用同一证书；保留 `drawable/piano_icon`。三种ABI、课程插画及远程视频清单与源码一致，APK不含MP4/WebM。分发复制后SHA-256与原始构建产物一致；机器记录 `build/release-0.1.72-artifact.json`。

## 安装包

分发文件：`D:/MyIdea/PianoForParkinson/releases/qinban-0.1.72-android-universal.apk`。

大小：**102,723,070字节（97.96 MiB）**。

```text
61747fb78564a4d60d51759b3d67296b108fe924420dceb319cd78516a159a51  qinban-0.1.72-android-universal.apk
```

校验文件：`D:/MyIdea/PianoForParkinson/releases/SHA256SUMS-0.1.72.txt`。签名证书SHA-256：`69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca`。原0.1.71本机包保留，本次新增0.1.72。

[GitHub Release](https://github.com/CapriChris/PianoForParkinson/releases/tag/v0.1.72) · [APK下载](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.72/qinban-0.1.72-android-universal.apk) · [校验文件](https://github.com/CapriChris/PianoForParkinson/releases/download/v0.1.72/SHA256SUMS-0.1.72.txt)。APK作为Release附件发布，不写入Git源码历史，本机releases目录保留同一文件。上传后核对GitHub返回的附件状态、大小和SHA-256，再公开发布。

## 适用范围与限制

沿用内部测试开发签名；包名 `com.pianoforparkinson.piano_practice`，版本0.1.72、构建73，包含ARM64、ARMv7、x86_64，目标API36。同包名同签名旧版可以覆盖安装，独立 `.validation` 包仍可并存。构建不包含服务端密钥，也不内置MP4/WebM，课程插画及远程视频清单须与源码一致。

既往Vivo后台提醒实测成功不代表新版或全部机型验收。厂商自启动和后台开关无法统一自动读取；定位/高亮参数可能被系统忽略，不能保证自启动条目闪两次。熄屏、锁屏、悬浮显示仍由系统控制；强行停止后需主动重新打开App恢复未来提醒。跨品牌页面跳转、后台送达、真机布局仍待设备复验。

## 构建参数

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=PD_API_BASE=https://ccqspace.site/pd-rehab/api --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

测试结束后正常执行pub步骤再构建，避免测试插件自动注册残留。未启用隔离包名或单架构选项，保留现有账号同步与AI网关配置。
