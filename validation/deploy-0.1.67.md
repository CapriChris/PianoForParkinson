# 0.1.67 舞蹈缓存联调包发布记录

日期：2026-11-12。用户明确授权“推送并部署”。App 仓库：`CapriChris/PianoForParkinson`，目标分支 `main`；发布前远端基线仍为 `25b27b09da050e658d62a297b9cc66df06f9a7fa`，没有覆盖队友更新。应用代码提交 `7236051`、`5488e9d`；后续提交仅维护发布说明及静态发布工具。

## 下载和适用范围

- [ARM64 联调安装包](https://ccqspace.site/pd-rehab/assets/app-releases/0.1.67/PianoForParkinson-0.1.67-dance-cache-QA-arm64.apk)，469,196,327 字节（447.46 MiB）。
- [SHA-256 校验文件](https://ccqspace.site/pd-rehab/assets/app-releases/0.1.67/SHA256SUMS.txt) · [发布元数据](https://ccqspace.site/pd-rehab/assets/app-releases/0.1.67/release.json)。
- 版本 `0.1.67+68`，包名 `com.pianoforparkinson.piano_practice.validation`，ARM64 debug QA；不是正式包覆盖升级，也没有创建 GitHub Release。
- SHA-256：`9253a5ecbba238777a5a12fac44c3e849909c1e9d03ae3481b7565612386a064`。
- 开发签名证书 SHA-256：`fef749f0575a3abbfd7f6d01a0b5108e09a9ec40de2c8ebefc97ba12e8565e8f`。原正式 0.1.66 使用另一开发证书，因此保留独立包名，不能将本包宣传为原正式包的无损覆盖更新。
- 安装后打开中文舞蹈即可联网播放；实际读取字节自动缓存。Fandango 保留随包。完整缓存通过本地 SHA 后可离线读取，部分缓存仍需网络。

## 本轮验证

Flutter 静态检查无问题；814 项测试通过，2 项现有 opt-in 跨端联网测试跳过。原生 104 项通过（含 12 项真实 Media3/HTTP 缓存测试），0 失败/跳过；APK 签名及归档内容已验证。推送前已再次执行同一组检查，结果保持 814 通过/2 跳过和原生 104 通过；本机日志为 `dance-cache-publish-analyze.log`、`dance-cache-publish-tests.jsonl`、`dance-cache-publish-native.log`。详细边界见 [联调记录](dance-stream-cache-20261112.md)。未连接手机，真机 HEVC、断网跨进程重开、弱网和系统中断仍未验收。

公网安装包 HEAD 200，长度匹配；头部、中部、尾部各 4096 字节 Range 均 206，并与本地 APK 对应字节完全一致。服务端完整 SHA 与本地一致，公开校验文件匹配。公网三段 MP4 各读 1024 字节均 206，Content-Range 精确匹配清单长度。未再次完整下载 447 MiB APK，不把抽样 Range 冒充完整公网下载校验。

既有 Web 首页 200。隔离 Chrome 实际点击总首页帕琴律动入口，进入 `/pd-rehab/login?redirect=/dashboard`，标题“登录 · 帕琴律动”；安装包链接成功触发浏览器下载，文件名正确，收到下载响应后立即取消以避免重复传输。健康接口正常、4 个模型 READY；匿名患者接口仍返回 401。

## 服务器变更

- 发布目录 `/var/www/pd-rehab/app-releases/0.1.67/`，仅新增 APK、`SHA256SUMS.txt`、`release.json`。
- `dist/assets/app-releases` 与 `dist-under-path/assets/app-releases` 均链接到 `/var/www/pd-rehab/app-releases`，复用现有静态资产路由。没有修改 Nginx 配置、端口或总首页注册表。
- 私有暂存与审计目录 `/opt/pd-rehab/releases/dance-cache-20261112-5488e9d/`。APK 校验后原子移动到公开目录，不保留额外大文件副本。
- 发布脚本：[publish_dance_cache_0167.py](../tools/publish_dance_cache_0167.py)。默认只读预检，显式 `--publish` 才写入；只允许预期旧 Web SHA、干净工作区、正确哈希及不存在的新版本。已发布后重复执行会拒绝覆盖。
- Web 后端源码仍为 `90d5e53162f9e673c931334dabb885daef46b272`，不迁移数据库，不重启服务。PD、Nginx、总首页及其他 5 个项目服务（共 8 个）的 ActiveState/MainPID 发布前后完全一致。
- 原三段视频及 `v1` 清单保留原字节和访问路径；没有改动患者媒体或业务数据。

## 回滚边界

这是增量静态发布，无代码切换或数据库回滚。若需要下架本包，只移除本版本三个明确文件，以及确认仍指向上述目录的两条 `app-releases` 链接；不递归删除 `/var/www/pd-rehab`，不修改 `dance` 链接，不恢复生产数据库，不重启其他服务。保留旧正式包及原视频不受影响。GitHub 回退使用新 revert 提交，禁止强推 main。
