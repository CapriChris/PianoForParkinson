# 0.1.57+58 按需下载版构建与验证

历史状态更新（2026-11-03）：本方案已按用户决定延期，0.1.58恢复随包离线视频。下文只记录未发布原型的构建和验证，不是当前版本。host-pending安装包已停用，不应继续分发；后续计划见[未来开发计划](../docs/未来开发计划.md)。

日期：2026-11-03。状态：本地内部测试，国内托管待配置；未发布新的GitHub Release。主入口lib/main.dart，非集成测试入口。版本号0.1.57，构建号58。

## 构建结果

| 安装包 | 包名 | 字节数 | 大小 |
| --- | --- | ---: | ---: |
| qinban-0.1.57-android-universal-host-pending.apk | com.pianoforparkinson.piano_practice | 96011487 | 91.56 MiB |
| qinban-0.1.57-android-universal-preview-host-pending.apk | com.pianoforparkinson.piano_practice.validation | 96011495 | 91.56 MiB |

两个包保存在原工作区releases目录，均包含ARM64/ARMv7/x86_64 AOT产物，沿用开发证书。包名、版本、构建号及签名核验通过；两个APK中均没有MP4或WebM文件。相比0.1.56主包659372452字节，减少85.44%。原视频文件未从开发机删除，仍用于上传国内托管。

```text
785c689ff9e4cb6e34c8913acbba452f975b5acf4eba7c99326fbe9b70762942  qinban-0.1.57-android-universal-host-pending.apk
d61c65aee8b78f2dece56444be5cd50b6b99fc51615ce8dc60c350f2b8f8b8f4  qinban-0.1.57-android-universal-preview-host-pending.apk
```

证书SHA-256：69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca。APK声明INTERNET和ACCESS_NETWORK_STATE，无CAMERA权限；未新增存储读取权限。APK中的下载清单与本机配置字节一致，地址全部留空，没有境外回退源。

主包构建：`flutter build apk --release --target=lib/main.dart`；旧预览版升级包追加 `--dart-define=ISOLATED_TEST_PACKAGE=true`。最后补充退出中不自动重开视频的保护后，两包均重新构建。

## 自动验证

- flutter analyze --no-pub：No issues found。
- 相关回归88项通过：下载层17项、下载界面8项、旧舞蹈播放流程10项，以及舞蹈历史、计划数据、通知、计划界面、按压和字号测试。
- 最后播放器修改后，下载界面与舞蹈流程18项再次通过（属于上述88项，不重复累计）。记录断言确认下载等待20秒不会生成训练时长。
- 下载层使用真实回环HTTP服务器测试200/206、Range/If-Range、暂停与跨实例恢复、忽略Range重写、区间错误、哈希不符重试、空间不足、未配置来源、离线缓存、版本隔离、删除互斥和错误状态。测试没有访问任何实际视频源。
- 下载界面验证显式同意、计费网络确认、离线提示、未配置来源、切换暂停、删除保留记录、中英文320dp/200%布局。native播放器以测试替身验证file类型数据源与原控制行为。
- 托管配置工具验证HTTPS配置干跑、拒绝HTTP及未授权配置变更、校验清单与原文件清单一致。未执行真实公网探测或写入下载地址。
- 通知回归中一个固定日期夹具已过期，改为相对当前时间的未来日期，保留跨午夜测试含义；未更改通知生产逻辑。

## 限制与下一步

团队尚无国内托管地址；四个视频尚未上传。因此此包可以验证体积和其余界面，未下载的舞蹈课程暂不可用，不应作为视频功能已上线的正式包分发。

按[部署说明](../docs/2026-11-03-视频按需下载与国内托管.md)上传原文件、检查HTTPS/Range/大小并配置地址后，需重新构建和在目标Android真机验证首次下载、暂停续传、离线观看、空间不足和清理。未配置网络源前不宣称真实云端下载或跨品牌手机验证完成。本轮没有安装/卸载用户设备上的App，也没有创建模拟器。

离开页面、切换部分或切后台主动暂停，后续手动继续；没有Android后台持续下载服务。下载完所有课程后仍会占用视频数据空间，只是无需随每次App更新重复分发。

本轮没有运行完整测试套件；0.1.56完整套件606通过/102失败的历史限制仍见[上一版验证](release-0.1.56.md)，不将专项通过表述为全套通过。机器可读报告及SHA256清单位于原工作区releases目录；日志在build/video-download-*.log，不进入Git。
