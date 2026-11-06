# 琴伴 0.1.61+62 构建与验证

2026-11-06 · 本机账号功能验收版；未发布 GitHub，未部署公网后端，未安装到用户手机。

## 安装包

- `qinban-0.1.61-android-universal.apk`：664,017,012 字节（633.26 MiB），本机位于 `D:/MyIdea/PianoForParkinson/releases/`。
- 包名 `com.pianoforparkinson.piano_practice`，versionName `0.1.61`，versionCode `62`；应用内常量与 `pubspec.yaml` 一致。
- Release 通用包，最低 API 24，目标 API 36，支持 ARM64、ARMv7 和 x86_64。
- `apksigner verify` 通过，证书 SHA-256 为 `69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca`，沿用此前开发签名，可覆盖安装签名相同的主包。
- 包内四段舞蹈视频的大小和 SHA-256 与资源清单一致；ARM64 AOT 库保留 `accountBackgroundMain` 后台入口。

```text
6e85f8046f199cd3fe6a934a49a970f3f51c2f3c3e3d839626bd05b19f62b9b9  qinban-0.1.61-android-universal.apk
```

## 本机验证

- `flutter analyze --no-pub`：通过，无问题。
- 完整 Flutter 套件：765 项通过、1 项跳过，无失败；随后增加真实 SQLite 账号隔离测试，并对账号与训练存储专项共 18 项复验，全部通过。
- Web 后端认证、跨端权限、同步与数据库迁移相关回归：47 项通过；随后增加回滚停用普通用户的安全测试，账号专项共 10 项复验，全部通过。
- 覆盖注册后 Web 建档、示例数据保留、重复注册事务、普通用户与工作人员权限隔离、跨患者访问拒绝、重复同步去重、刷新凭证轮换和撤销、密码修改/恢复、旧权限回滚。
- App 专项覆盖未登录及系统返回锁定、退出移除受保护路由、有效会话离线恢复、过期会话锁定、安全存储写入失败、并发续期、退出与迟到写入、账号数据库隔离及稳定设备 ID。
- 后台存储回归确认：独立后台打开数据库不结束仍活动的训练；交互启动仍保留原恢复机制。
- Android Debug 和 Release 编译均通过，包括 Keystore、文件锁与 WorkManager 原生代码。

## 构建命令

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

账号 API 默认 `https://ccqspace.site/pd-rehab/api`，可通过构建参数 `PD_API_BASE` 指定其他 HTTPS `/api` 地址。切换服务地址使用不同账号数据目录；不合并原服务记录。

## 联调边界

- 只读检查公网 `GET /pd-rehab/api/mobile/auth/me` 返回 HTTP 404；线上账号路由尚不可用。需要先部署本机 Web 配套代码，执行迁移 `n0c2d4e6f8a0` 并重启服务。
- 尚未进行本版真机、原生 Keystore 故障恢复、后台进程调度或线上注册/同步的端到端验收；编译和自动化测试不代表这些项目已完成。
- WorkManager 受系统调度、网络、电量及强制停止影响，不保证立即运行；后台仅补传结构化记录和计划，视频沿用既有流程。
- 本机日志：`build/account-analyze.log`、`build/account-all-tests.log`、`build/account-final-focused.log`、`build/account-release-build.log`；Web 日志位于其 `artifacts/mobile-account-regression.log` 与 `artifacts/mobile-account-final-security.log`。

[更新说明](../docs/2026-11-06-0.1.61-更新说明.md) · [部署与验收交接](../docs/2026-11-06-账号注册登录与自动同步交接.md)
