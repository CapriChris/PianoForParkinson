# 账号注册登录集成实施记录

## 基线和边界
- Web 重新克隆 GitHub main 7e1c731；Flutter 重新克隆 4dc63c2（0.1.60+61），不使用历史整合包覆盖。
- 本机查找未找到提示中的两个编号源码 ZIP；使用请求允许的最新真实 Git 仓库。账号后端 ZIP 的 13 个清单文件逐项 SHA-256 和 ZIP CRC 均已核验。
- 本地分支 codex/mobile-accounts-20261106；不 Push、不改生产、不重启。目标版本 0.1.61+62。
- 主训练数据库 v4、算法、指标、动作、音频和触摸逻辑保持。账号新增独立入口和目录；测试仍允许直接注入 PianoApp。

## 实施顺序
1. 后端逐文件审查合并：注册事务和患者编号、移动会话、普通账号权限；隔离数据库升级/降级演练。
2. Keystore 密文会话、刷新串行和退出代次；不保存明文登录凭据。
3. AccountRoot 在 restore 前拿全局前台锁，账号目录拿工作区锁，注入原 AppController 和 AutoSync；换账号先关闭旧数据库。
4. WorkManager 受限后台引擎只跑原同步器；活动前台使用同一协调器，不开摄像头/音频/模型、不恢复未结束训练。
5. 独立测试、真实本机 HTTPS 两端账号与同步闭环、完整回归、APK 和交付记录。

## 必要范围补充
训练录像原生存储原先为全局目录，cleanup 只收到当前库 known_ids；引入多账号后可能清理其他账号的合法录像。需要按账号工作区隔离 CaptureVault 命名空间，保留旧目录及原有加密/授权机制。此变更属于账号安全兼容，不修改录像分析算法。

## 最终实现

### Web
- 新增 `mobile_accounts`（用户 UUID→唯一患者 UUID）和 `mobile_sessions`，迁移 `n0c2d4e6f8a0` 的父版本为 `m9b1c3d5e7f9`。
- `/api/mobile/auth` 下新增 `register`、`login`、`refresh`、`me`、`logout`、`reset-password`、`change-password`。注册固定普通 PATIENT 身份，同一事务创建患者/编号/关联/首会话，不接受客户端指定角色或患者 ID。
- 15 分钟 Access Token + 30 天轮换 Refresh Session。数据库存刷新凭证/恢复码哈希；普通用户逐请求核对 session、路由白名单和患者级归属。原工作人员登录保留。
- 自有 bootstrap 不返回工作人员目录；`/plans` 支持本人计划；媒体 Cookie 同样核对移动会话撤销。
- 并发注册/轮换使用数据库事务和条件更新；SQLite 使用 BEGIN IMMEDIATE，非 SQLite 行锁路径未在实际其他数据库验证。进程内限流是补充，多 worker 上线需共享边缘限流。

### Flutter
- `AccountApplication` 成为正式入口，首次进入注册/登录页；恢复中不展示训练，退出/失效立即替换账号界面及 Navigator。
- 注册要求明确同步同意并展示一次性恢复码；支持恢复码重置、改密、退出。密码、Access Token、恢复码不持久化。
- Keystore AES-GCM + AtomicFile + noBackupFilesDir 保存加密刷新会话。轮换先持久化成功再发布 Access Token，代次和串行写保护退出/刷新竞态；患者 UUID 不允许静默变化。
- 离线仅恢复未到期的已验证账号；首次注册/登录必须成功联系后端。离线训练留在该账号空间，恢复后由原 AutoSync 上传。
- 目录为规范化服务地址和用户 UUID 的 SHA-256，不使用姓名或患者编号拼路径。换账号关闭全部旧库和录像服务，再释放工作区锁；旧访客目录不迁入新账号、不清空。
- `connectAccountAndSync` 使用返回的本人患者自动绑定。账号专属首次绑定同步起点为 0，避免首次绑定前离线产生的记录遗漏。
- WorkManager 联网一次任务 + 15 分钟周期任务；前台转调同一 AutoSync，后台只读已迁移主库、写独立同步侧库。全局会话锁/工作区 OS 文件锁防多引擎并发；不初始化训练、摄像头或音频，不上传面部视频。
- `PD_ACCOUNT_API_BASE` 编译参数允许指定可信 HTTPS 预发布 API，默认仍为既有生产地址；服务端未发布新接口时显示真实错误，不生成假账号。

## 修改清单

| 区域 | 文件 |
| --- | --- |
| Web 新增 | `backend/app/api/mobile_auth.py`、`backend/app/db/models/mobile_account.py`、`backend/alembic/versions/n0c2d4e6f8a0_mobile_accounts.py`、`backend/tests/test_mobile_accounts.py`、`backend/tests/test_mobile_account_migration.py` |
| Web 必要兼容 | `api/auth.py`、`api/deps.py`、`api/face_recordings.py`、`api/integration.py`、`api/router.py`、`db/models/__init__.py`、`db/models/staff.py`、`services/integration_access.py`、`tests/test_schema_bootstrap.py`（均在 backend 下） |
| Flutter 新增账号 | `lib/accounts/account_app.dart`、`account_pages.dart`、`account_session.dart`、`secure_store.dart`、`background_sync.dart` |
| Flutter 生命周期 | `lib/main.dart`、`lib/app/app_controller.dart`、`lib/app/piano_app.dart`、`lib/data/practice_repository.dart` |
| 同步与录像兼容 | `lib/integration/auto_sync.dart`、`remote_api.dart`、`training_capture.dart` |
| Android 新增 | `AccountVault.kt`、`AccountSyncWorker.kt`（`android/app/src/main/kotlin/com/pianoforparkinson/piano_practice/`） |
| Android 兼容/依赖 | 同目录 `MainActivity.kt`、`CaptureVault.kt`；`android/app/build.gradle.kts` 新增 WorkManager 2.10.1，仅用于受系统约束的结构化后台同步 |
| 测试/版本/复现 | `test/accounts/`、`scripts/run_local_sync_smoke.ps1`、`pubspec.yaml` |

原有主训练数据库保持 v4；没有改曲目、动作、KPI、音频/触摸算法。相关文件修正为原有 LF，避免整文件换行差异。没有新增 Dart 包或大型框架。

## 联调中真实发现并修复

1. Windows 沙箱的 Schannel 无法创建 TLS 凭据，原 readiness curl 不能访问本地 CA；测试脚本改用 Python ssl+urllib 验证同一 HTTPS 证书，没有关闭证书验证。
2. 实际 HTTPS 检查发现 `await logout()` 返回时后台撤销请求未完成。改为先立即注销本地、再等待有界的撤销尝试；离线保留加密补偿队列。真实旧 Access Token 回读现为 401。
3. 刷新响应即使用户 UUID 相同，也不能改成另一患者 UUID；新增回归阻止该身份漂移。
4. 最终静态审查发现录像异步操作可能跨越关库/换账号；新增运行任务集合，关闭等待所有操作完成，网络前后校验关闭与身份代次。真实 SQLite 的阻塞查询回归确认关库等待且无迟到请求，独立复查通过。
5. 调试 APK 重新构建曾复用受限 Gradle 守护进程，错误报告 Pub 插件不可写；关闭本项目专属缓存中的旧构建守护进程后重建通过，未改插件源码。

## 交付与边界

- Web 后端本地提交 `6e78ddfbaa8ac4c94ffcaab577f92088377a40ee`；Flutter 及文档提交见本分支最终 Git 日志。
- 两端本轮账号源码没有 Push、没有生产迁移或部署。用户后来单独要求的现有管理员密码调整已在生产完成并验证，但不属于账号功能发布；敏感值不写入文档或 Git。
- 测试详见 [测试报告](account_registration_test_report.md)，后续操作详见 [部署交接](account_registration_deployment_handoff.md)。
- 本轮没有可用 ADB 真机，因此物理摄像头、Keystore 跨重启、系统 WorkManager 调度和厂商省电行为必须由队友按交接验收，不能宣称已完成设备验收。
