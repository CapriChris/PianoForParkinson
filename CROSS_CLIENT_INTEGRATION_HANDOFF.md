# PD-Rehab-Web × PianoForParkinson — 2026-11-03 跨端集成交接

## 本次实际实现（并非宣布生产上线）

以 **PD-Rehab-Web 的患者 UUID、工作人员账号和 FastAPI** 为共享端，以 **Flutter 的原生训练、SQLite v4、音乐引擎** 为本地端。未删除/改名已有训练表、患者表、评估 API；未改写各端算法指标，也未修改任何线上服务器。

- Web 新增 `/api/integration/v1` 路由，工作人员复用 `/api/auth/login` Bearer JWT；支持分页患者及工作人员姓名同步、设备本地 Profile 与患者 UUID 绑定、原始 Flutter 训练/曲目/舞蹈/计划记录的**不可变幂等写入**、Flutter 查询 Web 评估与训练记录、软件端视频上传/面部分析任务、AI 问答。软件原始记录不会伪装成 Web 计算的同名 KPI。
- Web 新增数据库表 `device_patient_links`、`external_practice_records`、`mobile_face_jobs`、`expert_chat_turns`，新增 Alembic 修订 `j6e8f0a2b4c6`。需先备份、再迁移，不会自动篡改旧表。
- Web “随访与报告”新增“软件端记录”页签；顶部增加“AI 康复问答”入口，不增设管理员角色。
- Flutter 在设置页新增“患者同步、面部分析与 AI 问答”，使用 HTTPS API、手动选病患/绑定、同步本地**有效**记录、读云端快照、选/录视频上传、人工确认 CausalNet 候选关键帧、聊天界面。
- Flutter 增加 `lib/integration/` 和**单独** `pd_cloud_sync.db`。本机已有 `practice.db` 的 schema v4、迁移校验、哈希、原始历史和音频引擎完全不动。网络断开后本地练习仍工作；下次手动点“同步”可继续重试。JWT 只保存在当前页面的内存中，**不写入 SQLite**，重新打开需要登录。
- 两端的 API 源码协议以 `docs/cross_client_openapi_integration.json` 为准；同步记录 `schema_version=flutter-v4`、`record_type`、`source_record_id`、`device_id`、`local_profile_id`、`patient_id`，服务端留存来源、原始 payload、计算版本和 SHA256。

## 重要边界：当前是联通基础版，不是完成所有双向编辑

当前已实现：Web→软件的患者/工作人员基础资料与各类评估和训练**只读快照**；软件→Web 的钢琴/舞蹈/曲目/计划**原始记录**；面部模型调用与统一 AI 服务接口。

仍待下一阶段完成：服务器患者档案变更的持续**自动**增量推送、软件端编辑患者/医生信息及冲突合并、设备后台自动同步、跨端统一指标计算的经过验证的映射、同一设备多患者本地 Profile 严格隔离、手机离线端加密缓存与数据回收策略。不能将本版说成全量双向实时同步。

### 身份和权限

- 服务端患者 `patients.id` 是唯一主身份。Flutter 本地 `profiles.profile_id` 继续保留，通过 `device_patient_links` 明确绑定，不匹配姓名猜测身份。
- 单个 Flutter 本地 Profile **不能直接重新绑定另一名患者**，以免错误归属既有本地训练；若要支持多患者，必须先实现安全多 Profile。医生/管理员在业务产品上可以是同一权限层，但面向真实数据还必须补对象级授权（当前沿用原项目“已登录人员”权限模型）。
- 工作人员信息只同步 ID、显示姓名和登录 token 的临时身份，不同步密码哈希。禁止同步真实身份证号、患者面部原始素材到 GitHub。
- **必须使用 HTTPS**，Flutter 会拒绝 HTTP API 地址。手机访问 URL 示例：`https://ccqspace.site/pd-rehab/api`，该路径需要真实 Nginx 验证。

### 面部模型

- 软件仅负责摄像头/相册采集和结果展示，推理全在服务器。CausalNet 当前实际是 `negative/positive/surprise` 等模型自身类别，**不是强制七情绪**。
- 无真实权重时 `POST /face/jobs` 返回 503，不伪造结果；有 CausalNet 时 Job 初始 `REVIEW_REQUIRED`，软件可向 `GET /face/jobs/{id}/candidates` 查询候选，人工预览并选定后 `POST /face/jobs/{id}/review`，再读 Job 结果。其他已配置的适配器可直接异步运行。
- 当前使用 FastAPI `BackgroundTasks` + DB Job 行，**并非可水平扩展的持久作业队列**。服务重启后任务会标记失败，候选复核视频只保留有限时间；生产版应独立推理 Worker、队列及排队上限。成功分析的结果/媒体会按原 Web 评估服务保留，正式处理患者视频前必须确定保留、撤销、删除及访问审计规则。
- 不可用模型时，先接入真实 CausalNet 源码、权重和真实预处理环境；别拿模拟七分类当成功。

### AI 问答

服务端可配置 OpenAI-compatible API；默认不配置会返回 503。第一版是**知识和平台操作问答**，还没有外部资料 RAG 或真实患者数据工具，`patient_id` 仅用于核验/聊天归属，不会把患者病历发给模型。后续需要构建审核知识库和受控患者数据检索。API 密钥必须只存 Web 服务 `.env`，不要放在 Flutter、Vue 或 GitHub。

`.env`（不要提交实际密钥）：

```env
EXPERT_LLM_BASE_URL=https://your-provider.example/v1
EXPERT_LLM_API_KEY=YOUR_PRIVATE_KEY
EXPERT_LLM_MODEL=your-model-id
EXPERT_LLM_TIMEOUT_SEC=30
```

### 主要 API

| 功能 | 方法与路径（均在 `/api/integration/v1` 之下） |
|---|---|
| 账户与患者、医生简介分页下载 | `GET /bootstrap?offset=0&limit=100` |
| 绑定本地 Profile 至服务器患者 | `POST /bindings` |
| Flutter 原始记录上报，重试幂等 | `POST /records` |
| Web 读取 Flutter 的同步记录 | `GET /records?patient_id={uuid}` |
| Web 读取记录详细 JSON | `GET /records/{id}?patient_id={uuid}` |
| Web 原生患者历史只读快照 | `GET /patient-data?patient_id={uuid}&offset=0` |
| 模型和 AI 配置状态 | `GET /capabilities` |
| 上传面部视频 | `POST /face/jobs`，multipart |
| CausalNet 选帧建议 | `GET /face/jobs/{id}/candidates` |
| 确认选帧开始推理 | `POST /face/jobs/{id}/review` |
| 查询推理和真实模型输出 | `GET /face/jobs/{id}` |
| AI 康复知识问答 | `POST /expert/chat` |

所有新接口需要现有 `/api/auth/login` 返回的 Bearer token。错误保持 Web 统一 `{"error":{"code":"...","message":"..."}}` 格式。客户端重复提交同一 `(device_id,source_record_id,record_type)` 的相同 JSON 返回 `already_synced=true`；不同内容返回 409 拒绝覆盖。计划和计划日程按内容生成版本化来源 ID。

## 正式部署前必须做

1. 在目标服务器上**先备份**数据库及 `/data/uploads`、配置文件，检查磁盘容量、HTTPS 和反向代理；未获确认不得执行迁移/重启。
2. 激活正确后端 Python 环境，`python -m pip install -r backend/requirements.txt`（因模型可能另有依赖，需根据真实部署决定）；使用**真实** python-jose、bcrypt、MediaPipe 等，不使用测试替代品。
3. `cd backend && alembic upgrade head`，检查新四张表及原有数据数量。保留恢复方案。
4. 在真实后端执行 `pytest -q`；`cd frontend && npm ci && npm run build && npm run test`（按 package.json 实际脚本执行）。
5. `cd Flutter项目 && flutter pub get && flutter analyze && flutter test && flutter build apk`。确认 image_picker 可正常调用安卓相机/相册且 `INTERNET` 已声明。
6. 用无身份信息的测试患者进行端到端校验：登录 → 患者绑定 → Flutter 练习上传 → Web 随访读回 → Flutter 拉取 Web 记录 → 有真实模型的面部视频上传/选帧/结果 → AI 问答。
7. 安全性：对象级授权、数据加密/保留策略、日志脱敏、视频生命周期、速率限制、任务排队上限、重要异常告警。

## 已执行的测试（本交付环境）

- Python 新代码 `compileall`：通过。
- 新增 API/身份/幂等/冲突/模型不可用/AI 未配置的 5 个 FastAPI 单元/接口测试：**通过**。
- 额外运行 33 个 API 及核心业务相关回归：**通过**。
- 全部 Alembic 升级至新修订：**已在临时 SQLite 数据库完成**，共 20 张业务与迁移表。
- **限制**：本容器未预装 `python-jose`，测试使用了**外部临时的 PyJWT 接口适配**（该替代代码不包含在交付包），并调用系统 bcrypt；生产需再次用 requirements 真实依赖跑一遍。全量 Web 测试遇到本容器未装 `mediapipe` 的旧有视频测试失败（期望 VIDEO_UNREADABLE，却因模型依赖缺失返回 MODEL_UNAVAILABLE）。Web 前端 `npm ci --offline` 因缺少依赖缓存未成功，所以不能声称构建通过。此环境没有 Flutter/Dart SDK，**没有完成 Flutter analyze、flutter test、APK 构建或设备实测**。
- 面部模型实际推理及外部 AI 供应商在线调用：因缺真实配置/网络，**未实测**。
- 正式服务器：**未修改、未部署、未做真实生产联调**。

交付说明：这是可供下一阶段 Agent 在 Windows/服务器真实环境继续编译、联调、修复并部署的**源代码集成版本**。不可把未执行的测试或不完整的双向同步宣传为已经全部完成。
