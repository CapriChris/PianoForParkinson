# 自动同步 API 对照

| 功能 | 接口 | 权威和兼容 |
|---|---|---|
| 登录 | `POST /auth/login` | Web 权威；凭据只在内存 |
| 选择患者、工作人员 | `GET /integration/v1/bootstrap` | 登录或打开云端页面时分批读取授权档案；不保存目录到业务库 |
| 确认患者归属 | `POST /integration/v1/bindings` | 显式绑定设备、本地档案和 Web 患者 UUID；不允许覆写旧绑定 |
| 训练、计划快照、计划执行 | `POST /integration/v1/records` | 训练来源 ID 不变；服务端幂等；同内容计划版本不重复发送 |
| 自动拉取 | `GET /integration/v1/changes` | 绑定授权；服务端持久序列；事务应用 upsert/tombstone 和游标 |
| 旧历史读取 | `GET /integration/v1/patient-data` | 仅旧版回退，查询近期记录，明确提示不是增量 |
| 训练录像 | `/integration/v1/face/recordings` | 原独立上传与授权，优先保证成绩关联，既有模型流程保留 |

计划快照用 `snapshot_revision`、`daily_progress` 和独立来源记录。次数为次数；分钟类的 `completed_units` 为训练毫秒、`target` 为分钟。Web 对同一设备、档案、计划聚合，迟到低版本不覆盖高版本。Web 的原生训练计划是云端只读，未引入在 App 上覆盖 Web 临床计划的接口。患者和工作人员资料仍在 Web 管理；Flutter 没有此类可编辑页面。
