# 微信与手机号登录验证记录

日期：2026-11-12。App 基线 `e032966`；Web 基线 `20761b9`。本轮只完成源码和配置说明，无 APK、GitHub 推送或服务器部署。

## 已验证

| 检查 | 结果 | 本机证据 |
| --- | --- | --- |
| Flutter 全量测试（最终代码） | 826 通过、2 跳过 | `build/external-login-full-tests.log` |
| 登录界面与新增登录方式测试 | 23 通过 | `build/external-login-ui-tests.log` |
| Flutter 静态分析 | 无问题 | `build/external-login-analyze.log` |
| Android Kotlin 源码编译 | 通过，包含微信 SDK 6.8.40 | `build/external-login-kotlin-check.log` |
| 后端账号、第三方登录、数据库迁移与表结构 | 44 通过 | `web/artifacts/external-login-final-tests.log` |
| Android Manifest | 回调别名及目标有效，无新增短信读取/接收和电话状态权限 | XML 检查 |
| 阿里云 RPC 签名 | 含中文的固定输入与官方 SDK 签名一致 | 后端固定向量测试 |

Flutter 覆盖关闭服务提示、手机号校验、发送期间重复操作、重发倒计时、服务端 Retry-After、修改手机号后旧挑战作废、恢复码确认、同账号绑定不切换本地目录、微信 state 不匹配与取消授权。

后端使用测试提供方和每个测试独立的临时 SQLite 数据库，覆盖首次建档、重复登录复用身份、已有账号绑定、两个提供方登录同一患者、绑定冲突、客户端伪造身份、过期/重放/最多尝试次数、会话撤销与新鲜度、持久化短信额度、失败发送占预留、配置关闭、被停用用户和提供方响应检查。没有真实发短信或读取生产数据。

迁移测试在旧版本数据库创建账号和训练记录，再升级至新头；原有每一张表的全部行逐项相同，仅新增三张表，完整性和外键检查通过。没有绑定数据时回退可用；已有绑定时拒绝破坏性回退，绑定和旧数据保持原样。

## 后端全量回归的环境限制

全量首次运行：572 通过、14 跳过、6 失败（`web/artifacts/external-login-full-tests.log`）。其中一项为本轮迁移最初一律拒绝回退，现已改成仅在已有绑定时拒绝，并通过最终 44 项账号相关回归。

余下 5 项已在同一 Python 环境、独立临时目录中导出的**未修改 Web HEAD 20761b9** 上逐项复现，日志为 `web/artifacts/external-login-baseline-tests.log`：

- `test_assessment_sessions.py::test_finger_tapping_upload_rejects_non_video`：缺少 mediapipe，收到 MODEL_UNAVAILABLE。
- `test_upload_provenance.py` 两项上传测试：同样缺少 mediapipe。
- `test_causalnet_integration.py::test_optical_strain_matches_author_shift_and_forward_fill`：缺少 pandas。
- `test_system_and_models.py::test_system_info_counts`：用例固定要求 Python 3.11，本机虚拟环境为 3.13.15。

没有把这些失败改成跳过或放宽断言，不能宣称后端全量无失败。44 项账号回归均通过。

## 仍须真实环境验收

微信与阿里云短信服务均未开通，因此提供方适配器的真实认证、签名登记、短信送达、付费额度、微信安装/授权/回调、Release 混淆和公网服务器部署尚未验收。Kotlin 源码编译不等于完整 Gradle/APK 构建，也不代表微信真机回调已成功。

开通、部署、构建后按 `docs/2026-11-12-微信与手机号登录接入说明.md` 的真机清单，检查旧账号绑定前后患者编号、计划进度、断网补传和账号隔离。
