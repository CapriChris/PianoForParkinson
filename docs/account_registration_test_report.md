# 账号注册登录与自动同步测试报告

日期：2026-11-06。仅报告本轮本地真实执行结果。

## 基线与最终结果

| 检查 | 结果 |
| --- | --- |
| 最新 Flutter main 基线 | 752 通过、1 跳过、0 失败 |
| 最终 Flutter analyze | No issues found |
| 最终 Flutter 全量 | 770 通过、2 跳过、0 失败（剔除测试加载器隐藏事件后计数） |
| 新账号实际 HTTPS 联调 | 1 通过；独立临时 FastAPI、Alembic、SQLite、自建 CA、真实 Dart HTTP 与真实 SQLite |
| 原工作人员实际 HTTPS 同步回归 | 1 通过；不可变记录与增量回读 |
| Web 后端全量 | 573 通过、2 跳过、0 失败；3 项既有数值计算 warning |
| Web 账号安全/迁移/录像专项 | 33 通过 |
| Web 前端 `npm run test` | 339 通过、0 失败 |
| Web `npm run build -- --base=/pd-rehab/` | TypeScript 检查与生产静态构建通过 |
| ARM64 Debug APK | 0.1.61+62，独立 `.validation` 包名，编译及 APK v2 签名验证通过 |
| ADB 设备检查 | `adb devices -l` 为空；没有实际设备验收 |

Flutter 两个默认跳过项都是需外部 HTTPS 服务的 opt-in 测试。本轮通过脚本分别实际启动隔离服务并执行，两项各 1 通过，并非用默认跳过替代联调。Web 两个跳过项是可选外部 MicroFlow 源码测试；当前普通后端环境不具备该外部源码/依赖，本轮不修改或重新验证模型推理。

## 具体覆盖

- 注册两个普通身份，患者 UUID、编号及本地账号目录不同；普通用户不能读患者目录或绑定他人患者。
- 手机 Session 的恢复与刷新、并行刷新合并、持久化失败关闭身份、离线恢复和过期拒绝、患者身份漂移拒绝。
- 注册需显式同步同意；恢复码确认交接；根登录页返回键不能暴露训练。
- 服务端重复用户名/大小写工作人员用户名拒绝、并发患者编号不重复、刷新只能成功轮换一次。
- 改密/恢复码重置撤销会话；旧恢复码不能复用；退出后旧 Access Token 与媒体 Cookie 不能继续读取。
- 主训练库后台只读：不创建/升级缺失或旧库，不恢复/改写未完成训练；SQLite 实例实测，不是字符串检查。
- 两账号 CaptureVault 调用均携带各自 owner_scope，cleanup 和 readChunk 不共用命名空间；物理文件/Keystore仍待真机。
- 真实本机 HTTPS 中完成两次舞蹈目标计划，Web `/plans` 逐次回读 1/2 → 2/2；再次同步 `uploaded=0`，恢复后绑定 ID 不变。
- 带既有工作人员、患者和训练的 SQLite 实际升级 `m9→n0` 并回滚 `n0→m9`，旧数据与外键保持；回滚停用普通账号。

## 复现命令

Web 使用本轮隔离源码及测试数据库，从 backend 运行：

```powershell
python -m pytest -q -ra
```

Flutter 从本轮源码根目录：

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter json
# 按实际安装路径指定 Python、Flutter 和 OpenSSL
./scripts/run_local_sync_smoke.ps1 -WebRoot ../accounts-20261106-web -Python python -Flutter flutter -TestPath test/accounts/live_account_integration_test.dart
./scripts/run_local_sync_smoke.ps1 -WebRoot ../accounts-20261106-web -Python python -Flutter flutter
```

脚本必须由 PowerShell 运行，使用本机回环随机端口、临时 SQLite、测试 CA 和随机测试凭据，结束后停止测试进程。不要将测试入口改成生产 URL。测试输出不打印 Token、恢复码或真实患者资料。

## 本地证据位置

文件位于 Web 主工作区 `_deploy/`：

- `accounts-baseline-tests.jsonl`、`accounts-final-tests.jsonl`、`accounts-final-analyze.log`。
- `accounts-real-https-final.log`、`accounts-existing-https-final.log`。
- `accounts-20261106-web-qa/full-final.log`、`security-final.log`。
- `accounts-web-tests.log`、`accounts-web-build.log`。
- `accounts-apk-final-verification.log`、`PianoForParkinson-0.1.61-accounts-QA-arm64.apk`。

最终 APK 大小 686,695,541 字节；SHA-256：`346c84288ea438d8cadbd6a5955d34bd142029a1b60639d240a069cd35bdbd59`。版本与签名来自实际 apksigner/aapt 输出。

早期失败日志保留用于追溯，不作为最终通过证据。曾出现的退出撤销竞态已修复并由真实 HTTPS 复测；其他环境路径/TLS 问题见集成报告。

## 尚未执行

无真机，未实际验证 Android 后台联网调度、强杀/重启后的 Keystore、两个 Android 引擎文件锁竞争、物理录像、系统权限与省电模式。未重新验证真实模型精度或调用外部 AI 供应商。没有生产迁移、没有发布新账号 API。上述未验项目不能记为通过。
