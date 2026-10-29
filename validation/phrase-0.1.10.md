# 0.1.10 节拍连续、末拍收尾与当前项编号验证

日期：2026-10-16。范围仅为本轮变动：S2／M1 时间轴、后台保存、原生音频调度、训练页项数与相关布局。其他模式仅检查变动的当前项编号，不运行其完整练习套件。

## 修复与验证

| 项目 | 结果 | 证据 |
|---|---|---|
| S2／M1 最后一音到整拍结束才切页 | 通过 | 四档 BPM、提前／准时／延后输入、两组、判分不变、尾段暂停／技术恢复的领域测试；两模式真机末拍截图 |
| 背景保存快照 | 通过 | 两模式 worker 快照隔离、校验与行指纹一致性测试；真机两组保存及结果详情 |
| 六种模式当前项编号 | 通过 | 首项显示 1、当前项结束与下一项切换的领域测试；中英文界面测试 |
| 矮横屏编号可见 | 通过 | S2／M1 × 中英文，800 × 360 dp；V2359A 末拍界面完整显示 |
| Android 原生音频线程与焦点复用 | 通过本轮真机观察 | 编译成功；M1／S2 实际演示、正式按住与暂停恢复；系统焦点日志不再逐音申请；屏幕录制对照如下 |

单元／界面测试合计 **116 个唯一用例通过**：68 个领域测试、39 个界面测试、9 个受影响 S2 回归。重复复测不额外计数。静态分析无问题。

- [领域测试日志](phrase-0.1.10-domain.log)
- [界面测试日志](phrase-0.1.10-widgets.log)，[最终布局及末拍 20 项复测](phrase-0.1.10-short-landscape.log)
- [S2 回归日志](phrase-0.1.10-s2-regression.log)
- [静态分析](phrase-0.1.10-analyze.log)

## 真机独立包验证

Vivo V2359A，Android 16／API 36，2800 × 1260 px 横屏（800 × 360 dp），字体倍率 1.0。使用与正常应用不同的包名 `com.pianoforparkinson.piano_practice.validation`。应用版本 0.1.10+11，release 构建，仅显式测试包名开关不同。

- **M1 两组**：每组最后一键按住超过 400 ms，两个最后音均命中；其他目标故意不按。每组末尾仍可见未结束的全程进度，琴键灰显、时值条消失，提示“让最后一拍走完”；第一组后才出现下一组，第二组后才进入结果。结果 24/24，22 次漏拍、2 次命中、0 次时值不足、0 次窗口外输入，结果保存成功。
- **S2 两组**：第一组不按，测试普通暂停／继续；第二组最后一键按满后截图，此时全程进度未满。尾段点击暂停，至少三秒后仍停留暂停页，“重看演示”禁用；继续后完成。结果 16/16，15 次漏拍、1 次命中、0 次时值不足、0 次窗口外输入，结果保存成功。
- 未改变手机媒体音量、字体倍率、无障碍开关；系统日志开关仍为 `no`。没有安装／覆盖正常手机包，没有清空正常应用数据。测试结束卸载独立测试包并删除本轮已知 sdcard 截图、录屏与 XML。

证据：[M1 第一组末拍](../screenshots/physical-0.1.10-m1-tail-final.png)、[M1 第二组末拍](../screenshots/physical-0.1.10-m1-end-tail.png)、[M1 结果](physical-0.1.10-m1-result.xml)、[M1 详情](physical-0.1.10-m1-detail.xml)、[S2 第二组末拍](../screenshots/physical-0.1.10-s2-tail.png)、[S2 尾段暂停](physical-0.1.10-s2-tail-pause.xml)、[S2 结果](physical-0.1.10-s2-result.xml)、[S2 详情](physical-0.1.10-s2-detail.xml)。

## 连续性录屏观察

先移走记录统计后，真机仍在部分拍点出现可见停顿；进一步将原生 SoundPool／音频焦点调用移出主线程，并复用已持有的音频焦点。

| 演示录屏 | 时长 | 可见进度最大更新间隔 | P95 | 超过 100 ms 的间隔 | 倒退 |
|---|---:|---:|---:|---:|---:|
| M1，原生音频修复前 | 16.0 秒 | 249.1 ms | 34.6 ms | 6 | 0 |
| M1，原生音频修复后 | 16.0 秒 | 54.2 ms | 34.2 ms | 0 | 0 |
| S2，修复后 | 10.0 秒 | 50.5 ms | 34.2 ms | 0 | 0 |

对自有应用的 Android screenrecord 视频逐帧解码，测量整组进度条绿色右边缘发生更新的时间间隔；脚本为 [analyze_phrase_video.py](analyze_phrase_video.py)。录屏无音轨，结果只描述该设备、该片段的可见动画表现，不能代替声学延迟测量或所有设备的性能保证。

[M1 改前视频](physical-0.1.10-m1-demo.mp4)、[改后视频](physical-0.1.10-m1-after-audio.mp4)、[改后分析](physical-0.1.10-m1-after-audio.json)、[S2 视频](physical-0.1.10-s2-demo.mp4)、[S2 分析](physical-0.1.10-s2-demo.json)、[本应用焦点日志](physical-0.1.10-native-focus.log)。

## Android 自动化的实际边界

本轮仅 **1 个 Android 自动用例完成**：M1 封存组恢复、未完成窗口排除。后续菜单／两组测试在 Medium Phone 停止出帧，不能计作通过。切换 onlyPumps 策略仍停住；真实时钟性能用例已加入，但没有完整成功结果。

用户授权真机测试后，Flutter 调试包因 Vivo 系统日志关闭而无法发现 VM service。尝试开启日志的 ADB 命令被系统拒绝，设置未改变；用户打开的是 TalkBack 诊断界面，未要求其继续更改系统。后改用独立 release 包进行上述手动操作、录屏和结果检查。手动检查与自动用例计数分列，不把以前版本的六项自动测试当作本轮通过。

[M1 Android 日志](phrase-0.1.10-m1-android.log)、[真机自动化受阻日志](phrase-0.1.10-m1-physical.log)、[Medium Phone 分析](medium-phone-analysis-0.1.10.md)。

## 发布与兼容

- 正常包名 `com.pianoforparkinson.piano_practice`，versionName `0.1.10`，versionCode `11`；无 INTERNET 权限。
- 最终普通 release 编译成功。15 个内容／配置／声音资产与已归档 0.1.9 APK 逐项比较全部相同；数据库 schema 1、参数／指标版本与旧封存成绩不变。
- 使用开发签名，仍为 INTERNAL_DEMO／UNREVIEWED。正常发布包未覆盖安装到用户真机，真机验证使用独立包。
- [构建日志](phrase-0.1.10-release-build.log)、[APK 元数据](phrase-0.1.10-apk-badging.log)、[资产比较](phrase-0.1.10-assets.json)、[构建报告](../../releases/build-report-0.1.10.json)。
