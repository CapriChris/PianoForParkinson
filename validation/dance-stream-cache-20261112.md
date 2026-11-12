# 舞蹈在线播放与缓存联调记录（2026-11-12）

## 范围与基线

从 GitHub 最新 main `25b27b09da050e658d62a297b9cc66df06f9a7fa`（0.1.66+67）重新克隆，隔离分支 `codex/dance-stream-cache-20261112`。本轮仅改中文三段舞蹈的视频来源和 Android 播放缓存；不调整钢琴按键布局、账号、同步、训练计划、计时及记录算法。Fandango 仍随包。后续获得用户“推送并部署”授权，源码发布目标为 GitHub main，已将同一 QA 安装包开放服务器下载，详见 [部署记录](deploy-0.1.67.md)。未创建 GitHub Release，不覆盖原正式 App；视频服务器沿用已完成的独立静态托管。

## 使用

1. 打开中文舞蹈课程，选择片段即可播放，首次需要联网；不必先整段下载。
2. 播放器实际读取的字节自动写入 App 私有缓存；其他片段不会预取。切片、暂停、切到后台或退出时停止对应读取。
3. 完整字节通过本地 SHA-256 校验后，下一次可以直接离线读取，不请求远端清单或 HEAD。只看过一部分，跳到未缓存处仍需网络。
4. 遇到缓冲或网络错误，训练计时停止；网络恢复后由用户手动继续或重试，不自动增加有效训练时长。
5. 缓存可因容量限制和空间压力被淘汰；清理 App 数据会清理缓存。训练记录与缓存相互独立。

## 资源

基础地址 `https://ccqspace.site/pd-rehab/assets/dance/v1/`。三段分别为 `balance-six-part-1.mp4`、`balance-six-part-2.mp4`、`balance-six-part-3.mp4`。资源版本、精确长度及哈希见 [打包清单](../assets/video/remote_manifest.json)，原文件未经转码。缓存标识由 courseId、partId、resourceVersion、sha256 组成；URL 不作为身份标识。

原片均为 HEVC/AAC 720p，设备需要支持相应解码。服务器 Range、强 ETag、不可变版本路径已验证。公网静态视频不包含患者录像，患者媒体接口不受本轮改动影响。

## 技术实现

- `lib/platform/dance_video_source.dart`：从随包小清单解析资源、查询本地缓存状态，再创建网络控制器。英文课程继续 asset 控制器。
- `lib/features/dance_player_page.dart`：沿用原交互和 PlaybackLedger，补充网络错误/流量提示，初始化前接管控制器生命周期。
- `third_party/video_player_android`：从上游 2.12.2 做最小源代码分支，保留 BSD 许可；只对已知课程启用 Media3 CacheDataSource。无 Downloader、CacheWriter 或整文件 Dart 缓冲。
- 本地状态通道 `piano_training/dance_media_cache/v1` 的 `status(partId)` 不发送网络请求。内部资源头在 HTTP 请求前删除。
- 文件位于 Android noBackup 私有目录，共享缓存实例，容量上限 1 GiB，采用 LRU 和空间预算；完整性由实际区间及本地分块 SHA-256 验证。

## 自动化与安装包

| 验证 | 实际结果 |
| --- | --- |
| main 基线 Flutter 测试 | 804 通过，2 跳过，0 失败 |
| 新版 `flutter analyze --no-pub` | No issues found |
| 新版 `flutter test --no-pub --reporter json` | 814 通过，2 跳过，0 失败 |
| 舞蹈页面回归 | 18 通过，覆盖切片/拖动/计时/中断/初始化中退出与后台取消 |
| 原生插件 `:video_player_android:testDebugUnitTest` | 104 通过，0 失败/错误/跳过；包含 12 项缓存测试 |
| 公网三段 Range | 均 206，每段只读 1024 字节；Content-Range 与清单精确长度相符 |
| ARM64 QA APK | 构建成功，apksigner v2 签名验证通过；0.1.67 / code 68 |
| APK 文件核查 | 三段 MP4 均不存在；随包资源清单一致，Fandango 长度及 SHA-256 保持原样 |

两项跳过是原本按环境变量显式启用的真实账号 API/真实 HTTPS 增量同步测试；本轮没有开启其隔离服务 URL，不能声称这两项已经通过。

原生缓存测试使用实际 Media3 SimpleCache/CacheDataSource 和回环 HTTP 字节计数，验证部分读取持久化与离线复用、完整本地 SHA 后离线读取、错误哈希、文件缺失、LRU、版本隔离、读取多少只缓存多少、Range/416/长度错误、内部头移除、首个缓存写入失败时从未读位置回退、活动文件保护、动态空间预算和存储初始化失败时保留课程身份。暂停/stop/prepare 的生命周期覆盖是原生调用序列测试，尚无真机网络字节停止证据。

原生完整日志 `dance-native-final-plugin.log` 的 SHA-256：`088eea8b158804e979c2f37bfde8a515c17291ecbf21a2654294c3db0ab2ba51`。Dart 日志为 `dance-cache-tests.jsonl`、`dance-cache-analyze.log`；APK 核查命令：

```powershell
python tools/check_dance_cache_apk.py NEW.apk --baseline BASELINE.apk --output proof.json
```

同一 ARM64 debug QA 配置实际构建比较：基线 **689,230,763 字节（657.30 MiB）**，新版 **469,196,327 字节（447.46 MiB）**，减少 **220,034,436 字节（209.84 MiB / 31.925%）**。新版仍包含 344,420,928 字节的 Fandango，因此没有宣称全部视频均已移出安装包。

新版 APK SHA-256：`9253a5ecbba238777a5a12fac44c3e849909c1e9d03ae3481b7565612386a064`。基线 APK SHA-256：`80c72801e4dfbf9c2c3e38f9752df55561e97a45719a54e0d4af613a7b34b1b5`。

核心原生提交：`7236051aedf49b154cc1bbe5128a253d1bceb27b`。应用接入提交为 `5488e9d`，发布文档与受限发布脚本由后续提交维护。审查发现的加载中退出、后台读取以及缓存初始化失败时的身份识别问题均已修复；二次只读审查没有剩余已确认的重要问题。


## 真机验收（尚未执行）

当前 `adb devices -l` 未发现设备。以下不能被 JVM/Flutter 测试替代：目标手机的 HEVC 解码、实际弱网体验、断网跨进程重开、横竖屏以及来电后的手动继续。

建议使用独立 QA 安装包：先在线播放第一段一部分并退出，断网重开验证已缓存区间与未缓存区间；再完整播放片段且等待写入结束，关闭并断网重开验证整段可播。比较流量/服务端请求，确认离线完整缓存无 HEAD/GET。播放途中锁屏、切后台、切片、退出，确认不再增加视频读取，并核对训练时长和保存记录没有重复。

## 构建复现

Flutter 3.47.7 / Dart 3.13.5、实际构建 JBR/OpenJDK 21.0.10（Java source/target 17）、Android SDK 36 / NDK 28.2.13676358。先按 [资源说明](../assets/video/README.md) 恢复 Fandango，再执行 `flutter pub get`、`flutter analyze`、`flutter test`。同配置基线和新版均使用：

```powershell
flutter build apk --debug --no-pub --target-platform android-arm64 --dart-define=ISOLATED_TEST_PACKAGE=true --dart-define=ARM64_ONLY=true --dart-define=PD_CLOUD_INTEGRATION=true --dart-define=QIN_AI_GATEWAY=https://qin-ai-gateway-nbzaloppkk.cn-hangzhou.fcapp.run/ --dart-define=QIN_AI_PROVIDER_NAME=DeepSeek
```

QA 包名为 `com.pianoforparkinson.piano_practice.validation`，不覆盖正式 App。QA 为 debug 签名，不是生产 Release。构建使用原有网关参数，不包含密钥；本轮不改变 AI 配置。
