# 三课程与短信登录 App 验证（2026-11-13）

## 源码与范围

基线 main `d37230a`（含短信页面），保留 `e032966` 的缓冲指示、缓冲结束继续播放及中断后不擅自继续行为。`git apply --check ../media-sms-20261113-input/app-sms-login.patch` 报已存在/不适用，反向 `git apply --reverse --check` 成功；未重复应用补丁。当前工作树版本 `0.1.68+69`。

中英文界面均列出新平衡舞步六式 / New Balance Six（3段）、身心协调 / Brain and Body（4段）、律动与发声 / Move and Shout（3段）。默认课程固定为新平衡舞步六式，选择独立于界面语言；开播及切段只创建选中段控制器。新课程结果可直接重练同课程。

十段均从随包 `assets/video/remote_manifest.json` 解析到远程 HTTPS。此文件与协调生成的 `resources-v2.json` 完全一致；schemaVersion=1、top resourceVersion=v2，中文三个 item 保留既有 v1 身份、URL、长度和哈希。英文七段仅接收指定 courseId/partId/v2/完整 URL。Dart 和原生均拒绝未知身份及跨版本路径，保留本地 SHA、只读状态查询、私有缓存、活动文件保护、LRU、容量/空间限制及在线回退。

移除旧课程当前入口、关于页来源及 pubspec 视频打包项。旧课记录/结果仍可读取，混合四种 courseId 的数据库分页和详情完整性验证保留，未修改数据库模式或清理已有记录。现有账号密码、短信页面及微信隐藏逻辑未修改。

## 实际验证

| 检查 | 本轮结果 | 日志 |
| --- | --- | --- |
| 基线完整 Flutter | 829 通过、2 跳过、0 失败 | `build/media-baseline-tests.jsonl` |
| 测试驱动回归 | 英文不再自动选旧本地课、原生错误版本拒绝、结果重练同课三个回归均先红后绿 | `build/media-red.log`、`build/media-native-red.log`、`build/media-replay-red.log` |
| 最终完整 Flutter | 836 通过、2 跳过、0 失败 | `build/media-final-tests.jsonl` |
| 静态分析 | No issues found | `build/media-analyze.log` |
| 登录/原账号 UI | 26 通过 | `build/media-sms-tests.log` |
| 原生插件完整测试 | 106 通过，0 失败/错误/跳过 | `build/media-native-final.log`、`build/video_player_android/test-results/testDebugUnitTest/TEST-*.xml` |
| diff 空白检查 | `git diff --check` 通过 | 当前工作树 |

两项跳过：`actual mobile account API preserves own records across refresh and rejects foreign identities` 与 `Flutter sends a single immutable record and receives a real Web delta over HTTPS`，需要显式隔离测试服务环境变量，未计入通过。首轮新目录未含历史随包视频，无法构建基线测试资源包；从既有验收目录复制同一文件后完成基线。当前版本不再打包此文件。SQLite hook 使用既有目录已验证缓存；未下载 DLL。原生第一次受限执行无法读取 Pub 缓存，获准使用既有本地缓存后完成测试；未新增外部依赖。

新增覆盖：两界面均发现三门课程、逐一选择两门英文课并切至末段且未预取其他段；十个资源只查询各自本地缓存状态；退役/错误身份拒绝；旧课结果仍显示；新课程结果重练同课；三个新旧课程及旧课历史详情可验证；原生十身份与版本/路径白名单、英文身份缓存持久化重开及版本隔离。Media3 既有真实回环 HTTP、SHA、LRU、缓存错误回退测试全部仍在106项内。

## 交付边界

构建/签名/APK 大小、静态资源在线 Range、生产发布、GitHub 推送与真实手机号测试由协调发布流程另记。本记录只描述本地实际验证，不声称已真机验收或已发送短信。目标 Android 的 HEVC 解码、弱网、后台/切片后网络停止、跨进程完整离线缓存仍需设备验收。

构建环境为 Flutter 3.47.7 / Dart 3.13.5，Android SDK 来自相邻 `android-sdk-autosync`。每次 Flutter 命令设置 ANDROID_HOME/ANDROID_SDK_ROOT，原生使用相邻 gradle-autosync、android-user-autosync 及 JBR21。APK 可用 `python tools/check_dance_cache_apk.py NEW.apk --baseline OLD.apk --output proof.json` 校验：十段清单与源码一致、全部 MP4/WebM 不在包内，并输出真实大小和哈希。
