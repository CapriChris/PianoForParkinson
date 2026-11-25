# Web / Android 完整安装包更新兼容审计

本次独立交付基线：仓库 PianoForParkinson，分支 codex/app-integration-followup，源自 origin/feature/android-apk-updates，Git HEAD 6f4c8cc（包含队友 3ee3763 APK updater）。源码版本 0.1.73+74，package com.pianoforparkinson.piano_practice。未重用旧隔离目录 App 的 5f7525e 或 18ffbb7。

此次只增加本审计文档；Dart、原生实现、插件、pubspec/lock、包名、签名、版本、App ID 全部保持队友基线。没有 Shorebird 配置或依赖，没有创建 Shorebird Release/Patch。真实机制为完整 APK 下载并经 Android 确认覆盖安装，不是 Dart 热补丁。

队友已有 docs/android-apk-update.md 与 lib/platform/apk_updates.dart 定义唯一默认清单：https://ccqspace.site/pd-rehab/assets/app-releases/latest-android.json。保留 PD_ANDROID_UPDATE_MANIFEST 联调覆盖；字段 schemaVersion=1、packageName、versionName、versionCode、apkUrl、sizeBytes、sha256、notesZh、notesEn。APK 与清单同源 HTTPS，均不跟随重定向，APK 哈希/字节数验证成功后才允许系统安装。无需新增 App 接口或另一套升级框架。

Web 修改在独立 Web 分支中，读取同一 latest-android.json，并使用其 apkUrl；本地 preparation 脚本从已批准实包生成该协议，服务器另行校验原证书、包名与版本。没有修改或发布 App。

实际回归（2026-11-19）：Flutter 3.47.7，flutter analyze 无问题；完整 flutter test 911 通过、2 跳过、0 失败，未删除/更改旧测试。pub get 未更改依赖版本。已有 SQLite 官方 GitHub DLL 被放入本地忽略 cache，由依赖自身验证原哈希；未修改 SQLite 实现。完整回归与静态检查的实际日志为 `validation/codex-followup-test.log`、`validation/codex-followup-analyze.log`，留在本地忽略目录且不提交。

只读查询 GitHub 最新公开 Release 为 v0.1.72（2026-11-14、构建73），其正文明确使用原内部测试开发签名。该旧包不是当前基线 0.1.73+74 的批准正式最新版，未拿来替代当前代码。默认清单实测404；此时客户端正常使用。当前 android/app/build.gradle.kts 仍是队友原有 debug 签名配置，此次按用户范围不更改签名。正式原证书及已批准最新版 APK 仍需发布负责人提供并独立核验，不生成新钥匙。

未完成的验收：正式 APK 下载/覆盖升级、真机安装确认、安装后会话/本地历史/账号隔离/训练/离线重试/视频与自动同步。未连接真机，不能将单元测试计作这些验收成功。未部署/推送/创建 Release/上传产物。

## 实际隔离 HTTPS 联调补充

使用现有 `scripts/run_local_sync_smoke.ps1` 分别启动独立 loopback HTTPS Web 实例，连接本次独立 Web 克隆的真实 FastAPI；每次使用新建的 `.dart_tool/local-sync-qa-*` SQLite、目录和临时证书。测试完成由原脚本停止对应服务器。未改产品代码，未访问生产数据库或真实患者，未关闭 TLS 证书校验。

- `test/integration/live_sync_smoke_test.dart`：1 通过、0 跳过、0 失败。实际 HTTP 请求验证本地已绑定训练记录上传、重复同步零重复上传、两次舞蹈记录与 daily progress=2、Web 新建评估的增量回传，以及解绑后 403/清除云端视图。未绑定历史没有错误上传。
- `test/accounts/live_account_integration_test.dart`：1 通过、0 跳过、0 失败。实际移动账号注册/登录、不同账号患者与目录隔离、越权绑定/员工患者列表 403、两条训练的计划进度、无重复上传、刷新恢复身份与绑定、退出撤销访问令牌、恢复码轮换/旧码拒绝、改密等断言通过。

本地真实执行日志：`validation/codex-followup-live-sync.log`、`validation/codex-followup-live-account.log`。这两项是原全套默认跳过的 opt-in 测试，本次显式启用，不能将结果叠加成新的全套统计。使用合成记录及桌面 SQLite FFI，账号存储 fixture 为 MemoryVault；它们验证真实 HTTPS API 与同步/账号逻辑，不证明 Android Keystore、实际 APK 安装、真机训练/视频或生产验收。原全套结果仍为 911 通过、2 默认跳过；两项独立 opt-in 均通过。


## 2026-11-20 推送前复核

队友的远程feature/android-apk-updates现为98a122f，比本轮6f4c8cc基线新增5cbf055和98a122f。实际差异为README、练习页移除姓名和0.1.73预发布验证说明，没有修改接口、清单协议或签名。按协作要求不自动合入，本轮分支仍仅含审计文档；上述911项和两个HTTPS实测对应本轮基线，不能说已全量复测98a122f。

GitHub v0.1.73现有候选APK，是明确标注的预发布（isPrerelease=true），大小102920214字节，公布SHA256为457eff09c8852865d4a719d2039d41b4369c0c1679128c4cdf227a34ca7a9d5c。队友记录真机覆盖安装仍待验证；没有把它替换成正式服务器下载，也没有更换签名。此更新纠正前面“初次核查仅见v0.1.72”的时间快照，不代表生产已发布。

## 分支交付结果

独立分支已推送，草稿 PR：https://github.com/CapriChris/PianoForParkinson/pull/1 ，目标分支为队友的 feature/android-apk-updates。Web 草稿 PR：https://github.com/WuChangqing1/PD-Rehab-Web/pull/2 。没有合并 main，没有部署生产；APK 下载地址与热更新按用户最新要求暂缓后续操作。
