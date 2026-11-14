# 琴伴 0.1.71+72 构建与验证

日期：2026-11-14。基于已发布0.1.70后的本机提醒功能改动构建；本次没有提交/推送 Git，也没有创建 GitHub Release、替换线上包或安装到手机。

后续公开发布见 [0.1.72构建与验证](release-0.1.72.md)。本文保留0.1.71本机构建的历史结果和摘要。

## 更新

通知图标资源保留修复、自动申请标准通知/准时提醒权限、自启动和后台活动分别“去开启”、返回后复查，以及未核实状态的准确展示。计划提示卡支持红色“不再提醒”和“本次关闭”，按钮与状态文案对应改为“提醒设置”。设置中增加始终可用的“通知与提醒”。APK版本、App内显示和新训练记录版本仍为 `0.1.71`（构建72），按要求覆盖同版本本机安装包，不改写历史记录。详见 [更新说明](../docs/2026-11-14-0.1.71-更新说明.md)。

## 本轮验证

- 按用户要求只运行相关 Flutter 测试：**56项通过、0失败**。覆盖授权/拒绝/重试、各按钮独立跳转、生命周期复查、临时/永久关闭提示、取消弹窗、计划编辑和提醒调度，以及中英文320dp/大字体布局；日志 `build/reminder-layout-20261114-tests.log`。发现并修复英文大字体弹窗溢出；新文案加入断言。
- 静态分析 No issues found，日志 `build/reminder-layout-20261114-analyze.log`。
- release 通用 APK 构建成功，版本 `0.1.71+72`，包名 `com.pianoforparkinson.piano_practice`；包含 ARM64、ARMv7、x86_64，目标 API36。版本与 `pubspec.yaml`、`contracts.dart` 一致。
- APK 签名验证通过，证书 SHA-256 `69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca`，与本机0.1.66及0.1.70包一致，仍为内部测试开发签名。同包名同签名旧版可覆盖安装；独立 `.validation` 包不受影响。
- 使用 aapt2 实际确认 APK 包含 `drawable/piano_icon`；三门舞蹈的插画及十段资源清单与源码逐字节一致，确认无 MP4/WebM。
- APK复制到 `releases` 后重新计算 SHA-256，与原始构建产物一致；版本、大小、摘要等机器记录位于 `build/release-0.1.71-artifact.json`。
- 最终构建日志 `build/reminder-layout-20261114-build.log`，包含 Kotlin 设置桥接接口。测试结束后正常执行pub刷新生成文件，再构建release。
- 既往Vivo后台提醒复测不代表这个新版安装包和所有品牌均完成真机验收；跨品牌跳转、真实提醒及系统条目高亮仍待设备复验。已传入包名与高亮参数，但厂商系统可忽略，无法保证自启动条目闪两次。熄屏/锁屏/悬浮通知仍需在系统中设置。
- 覆盖前原0.1.71包及校验文件已备份到 `D:/MyIdea/PianoForParkinson/recovery-data/0.1.71-before-reminder-layout-20261114/`，旧包SHA-256为 `93703bde81bb3baee397573dfd19aae9a718646e9206588ce08a318ff0a78ed6`。

早期首次0.1.71构建曾运行全量883项通过、2项既有联网测试跳过，日志 `build/release-0.1.71-tests.log`；这是历史结果，本次没有重跑全量测试。早期 `--no-pub` 构建曾遇到生成的测试插件注册残留，后通过正常pub步骤重建解决，无需手工删除插件代码。

## 本机安装包

[qinban-0.1.71-android-universal.apk](../../releases/qinban-0.1.71-android-universal.apk)，**102,657,534字节，约97.90 MiB**。

```text
ebe284279d3aa3fa07c7648daed9e504e33f1dece3bf21796c246d8a27a43fff  qinban-0.1.71-android-universal.apk
```

校验文件：`D:/MyIdea/PianoForParkinson/releases/SHA256SUMS-0.1.71.txt`。APK及校验文件仅位于本机分发目录，本轮未上传 GitHub。

## 构建参数

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=PD_API_BASE=https://ccqspace.site/pd-rehab/api --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

保留 HTTPS 账号服务、云端同步和既有阿里云 AI 网关配置；未启用隔离包名或单架构参数，没有加入任何服务端密钥。
