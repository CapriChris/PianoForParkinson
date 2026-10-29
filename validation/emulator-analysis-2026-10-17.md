# 模拟器偶发停止出帧分析（2026-10-17）

本轮读取配置和日志，并在独立测试包中复测 M1；未修改原 Medium Phone 的配置、驱动、镜像、快照或正常应用数据。原始快照见 [emulator-2026-10-17.log](emulator-2026-10-17.log)。

## 已确认的事实

1. Windows Application Event 1000 记录 **4 次独立 qemu 宿主进程崩溃**：10 月 14 日 13:23:26，以及 10 月 16 日 19:48:19、21:38:01、21:40:01（北京时间）。故障进程都是 `qemu-system-x86_64-headless.exe`，模块 `combase.dll`，异常 `0xc0000602`（fail-fast）。这不是应用内部 Dart／Java 异常；也不能仅凭 DLL 名就认定显卡或内存是根因。WER 归档目录可列出，但其内容受限，未取得调用栈。
2. 当前运行的是 Android Emulator **36.6.11**、API 37.1 Google Play 16 KB x86_64 镜像、嵌入 Android Studio 的隐藏 Qt 窗口（`-qt-hide-window`）、GPU auto、Quick Boot。旧记录中的停止出帧与上述 headless 进程崩溃需分开分析。
3. config.ini 写着 2,048 MB，但 `/proc/meminfo` 显示客体实际内存约 **4 GB**，当时可用约 2.1 GB；宿主约 32 GB、可用约 12.6 GB。不能把“配置写了 2 GB”直接当作本次卡死原因。官方说明 API 37 会强制提升到至少 4 GB，与实际读数一致。[Android Emulator 版本说明](https://developer.android.com/studio/releases/emulator)
4. 机器同时存在 Intel 核显、NVIDIA RTX 5060 Laptop GPU 和 GameViewer 虚拟显示适配器。这使图形设备选择／嵌入显示链路成为值得对照的方向，但仅有适配器清单不能证明驱动冲突。
5. 现存 Android crash 缓冲区为空；正常应用退出记录主要是用户移除任务／更新包，没有从这些现存记录中取得应用 ANR 或内存杀死的证据。日志可能轮换，这不证明历史上从未出现过应用问题。

## 当前判断

**用户补充：停止出帧只发生在 M1“交替按键”。因此首先沿 M1 的示范、连续节拍、输入和保存路径定位；宿主模拟器崩溃记录不能代替 M1 的现场证据。** 精确阻塞点尚未确认，也没有依据直接归因于 RAM 不足。

M1 的 12 拍示范在 40 BPM 下持续 18 秒，两组练习还包含连续进度重绘、节拍／琴音及定期保存，暴露连续渲染问题的时间较长。这解释了需要重点对照的工作负载，**不是已证明其负载导致卡死**。此前应用内同步保存与逐音申请焦点的问题已分别修复，不能声称 qemu 的 COM fail-fast 因而被修复。

本轮在原 Medium Phone、独立测试包中运行 M1 三项用例全部通过：已封存组恢复、两组 24 项逐项输入／保存／趋势、真实时钟示范和参考声音／按住／暂停继续／返回保存，合计 82 秒。第二组开始和首项均经过，未复现持续停止出帧。见 [M1 回归日志](m1-0.1.13-emulator.log)。`emulator-stall-20261017-084304` 是抓取工具的自动目录名，实际是该通过流程中的观察快照，不能将目录名当作一次故障。

随后运行“18 秒 M1 示范＋每 2 秒后台保存”的真实时钟专项，**复现持续停止出帧**。08:48 至 08:49 的两次 VM 读取均为 `_debugFrameNumber=556`、`_hasScheduledFrame=true`、`_expectingFrame=true`、`_framesEnabled=true`、`_schedulerPhase=idle`、`lifecycle=resumed`。Dart VM 服务可响应，调用栈为空；AppController 为 busy=false、storageError=null、_pendingFlush=null；引擎已到第一项 cue，等待界面呈现提示后回报锚点。这与“Dart 正在同步计算／SQLite 一直占用 UI”不相符，阻塞发生在请求帧之后、下一帧返回之前的链路。Flutter 官方说明 scheduleFrame 请求之后依靠系统 Vsync 驱动下一帧，因此应优先检查 Flutter 引擎／Android Vsync／模拟器图形表面链路，而不能仅以业务模式名称断言判分算法死循环。[Flutter scheduleFrame 文档](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/scheduleFrame.html)

该实例使用 Impeller OpenGLES。额外调用一次 `ext.ui.window.scheduleFrame` 得到 Success，画面仍未恢复；未将定时重复请求帧写入产品当作修复。读取 native 线程栈被 debuggerd 拒绝（root is required），未提升权限、未取得 native 栈，因此尚不能具体归到 Impeller、驱动或系统 Vsync 的某个函数。收集完后仅停止独立测试包，专项记录为**未完成／失败**，不计通过。证据：[帧状态一](m1-0.1.13-binding.json)、[帧状态二](m1-0.1.13-binding-second.json)、[控制器](m1-0.1.13-controller.json)、[引擎](m1-0.1.13-engine.json)、[专项日志](m1-0.1.13-animation.log)；现场系统快照位于 `emulator-stall-20261017-084822/`。

这是 debug 集成环境中的复现，不能单凭它证明所有正常 release 停帧都具有相同调用链；需要同样步骤的渲染器及发布模式对照。也没有据此把现有 Windows qemu fail-fast 与本次帧等待合并为同一故障。

随后在同一 AVD、同一用例和独立测试包下，仅增加 Flutter 启动参数 `--no-enable-impeller` 做 Skia 对照，28 秒完整通过：18 秒示范记录 442 帧、9 次保存，帧构建 P95 14.126 ms、最大 118.466 ms，示范节拍最大请求迟到 21.739 ms。见 [Skia 对照日志](m1-0.1.13-skia-animation.log)。这是本轮最有区分度的证据，**将 Impeller OpenGLES 与当前模拟器图形／Vsync 组合列为优先方向**；只有一次同流程对照，不能认定根因已证明或保证关闭 Impeller 后永不发生。官方支持在开发调试时用该参数关闭 Impeller。[Flutter Impeller 文档](https://docs.flutter.dev/perf/impeller)

可重复本轮隔离对照：`flutter test integration_test/phrase_animation_test.dart -d emulator-5554 --dart-define=ISOLATED_TEST_PACKAGE=true --no-enable-impeller`。正式包未加入猜测性的渲染器切换或自动强刷帧逻辑；原 AVD 配置不变。

教学自动截图流程也完整通过并产出 10 张图。旋转和释放截图用 ImageReader 表面时曾记录 BufferQueue abandoned／EGL_BAD_SURFACE，随后流程继续并完成；这是图形链路观察项，不能拿它证明 M1 的偶发停帧已经复现或找到根因。见 [截图流程日志](tutorials-0.1.13-lessons-android.log)。

本机 Emulator 版本落后于当前官方稳定版 37.2.12。37.1.11 的发布说明还列出 API 37 镜像所需的新增 Vulkan 扩展支持，说明旧模拟器与新系统镜像的组合值得优先做版本对照；**这不是本机问题已经被某个更新修复的证明**。[官方版本说明](https://developer.android.com/studio/releases/emulator)

## 建议定位顺序

1. 再次停止出帧时，先运行 `app/tools/capture_emulator_stall.ps1` 保存宿主进程、Windows 故障、SurfaceFlinger、应用帧统计、客体 CPU／内存和 logcat；在抓取前不要重启。若 adb 也不响应，应记录该现象和具体时间。
2. 用独立 AVD／测试数据，对比“独立窗口＋冷启动不加载快照”和当前嵌入窗口＋Quick Boot。若只有嵌入窗口停住而客体／独立截图仍更新，定位显示传输；若应用不更新但系统界面更新，定位应用或 Flutter；若整个客体不更新，定位模拟器／图形后端。
3. 备份后对 Emulator 新稳定版做同流程对照；如仍出现图形问题，再分别做 Hardware／Software 后端对照。一次只变一个条件，不用清空现有 AVD 数据代替定位。官方将后端切换列为图形兼容问题的排查方式，并说明 Vulkan 快照存在限制。[官方故障排查](https://developer.android.com/studio/run/emulator-troubleshooting)
4. 宿主再次 fail-fast 时，需要相应 WER dump 和线程栈才能具体定位 `combase.dll` 的触发链。当前没有该证据，因此不提供确定的驱动／Windows 根因结论。

本轮未自行升级 SDK、切换 GPU、关闭虚拟显示驱动或重置模拟器。抓取脚本只读，不停止应用，也不清除数据。
