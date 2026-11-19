# 患者姓名编辑与双向同步：0.1.73+74

日期：2026-11-19。源分支基线 `5f0cebb`，原版本 `0.1.72+73`。
工作目录：`D:/CodingData/Competition/PD/PD-Rehab-Web/_deploy/staff-accounts-20261118-app`。

## 行为

- 我的账号展示唯一的患者姓名，提供“修改姓名”；首页和训练页使用同一份 `patient.name`。不再把内部 username 展示为患者姓名。
- 注册昵称文案改为“姓名”；保留旧账号密码凭据，字段文案改为“登录账号 / Login account”。不改 username、user ID、patient ID 或数据库目录。
- `PATCH /mobile/auth/profile` 发送 `display_name` 和编辑时的 `expected_name`。仅在服务器确认且安全会话写入成功后报告姓名已保存。
- 409 后 GET me 获取最新姓名，保留输入，并要求用户再次明确确认；不自动覆盖医护端修改。
- 离线与保存失败保持编辑器并显示错误，不创建姓名修改重试队列。服务器已接受但本机安全存储失败时不显示成功，下一次刷新可重新取得服务器结果。
- 登录/refresh 响应、现有账号连接及前台/后台同步路径刷新共享姓名。GET/PATCH 只合并安全会话中的 user/patient，不写本地训练记录或 settings，不更改凭据过期时间/device ID/账号数据库分区。
- epoch 与请求修订号防止退出后的迟到响应、旧 GET 或先前 refresh 将姓名回滚；refresh 仍保留新轮换的 refresh token。
- 同意授权流程未改；舞蹈、提醒、节奏、原生代码及训练记录算法未改。训练页仅增加姓名展示。

## 验证

使用 `_deploy/flutter-3.47.7/bin/flutter.bat`。

1. TDD 初次 5 个 API 用例：4 个按预期失败（会话姓名不刷新、PATCH 不持久化、迟到 GET、退出后回复），实现后 5 个通过。
2. 新增两个并发用例先失败（保存期间 GET、先发 refresh 回滚姓名），修复后通过。
3. 新姓名 API/UI 定向测试共 13 个通过，覆盖凭据/目录保留、落盘失败、离线、409、旧 GET、退出、refresh token 轮换，以及 390x844 手机中英文 2 倍字体编辑器、旧编辑器跨账号提交阻止。
4. 全量 `flutter test --no-pub --reporter expanded`：**908 passed, 2 skipped**。跳过为既有 opt-in 本地 HTTPS backend 测试：`test/accounts/live_account_integration_test.dart` 和 `test/integration/live_sync_smoke_test.dart`，未设置测试后端环境变量。其余全量用例包含账号切换数据库/计划/设备隔离、历史与记录相关既有回归测试。
5. 修改登录账号文案后：`flutter test --no-pub test/accounts --reporter expanded`：**57 passed, 1 skipped**（同上 account HTTPS opt-in）。随后同步 `appVersion` 常量为 0.1.73。最终增加旧编辑器阻止跨账号提交与编辑期间后台刷新不更新 expected_name 的回归后，重跑全量得到上述 908 passed；该结果覆盖最终代码。
6. About 当前版本定向测试 1 passed。
7. `flutter analyze --no-pub`：**No issues found**。`git diff --check` 通过。

完整输出在本机忽略文件 `validation/patient-name-full-tests.log`、`validation/patient-name-account-tests.log`。

## 边界与交接

未运行真实手机或已部署服务器的端到端姓名同步，未构建 APK，未 stage/commit/push/deploy。中英文 2 倍字体编辑器通过 widget 测试；尚未做带真实账号的训练界面手机截图验收。真实后端须实现 PATCH profile/GET me 约定，SMS 新账号的 canonical patient.name 应为可读姓名；App 不以内部 username 回退。父任务负责 APK 构建及线上验收。
