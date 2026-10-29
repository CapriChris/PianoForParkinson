# Medium Phone 崩溃与停止出帧分析

日期：2026-10-16。按用户要求只分析现有模拟器，不修改其配置、驱动、系统镜像或用户数据。

## 能确认的事实

Windows Application 日志在 **2026-10-16 19:48:19（北京时间）** 有一次 Event 1000：故障进程 `qemu-system-x86_64-headless.exe`，故障模块 `combase.dll`（10.0.26100.9711），异常码 `0xc0000602`，PID `0x7BB0`。随后两条 Event 1001 是同一故障的 Windows Error Reporting 记录，并非另外两次崩溃。PID 与先前临时软件渲染实例的启动日志一致，说明软件渲染也不能保证不会发生这类宿主进程故障。

Microsoft 将该异常码定义为 `STATUS_FAIL_FAST_EXCEPTION`：异常处理程序不会被调用，进程立即终止。这是 Windows 上的模拟器进程故障，不能当成 Android 应用的 Dart／Java 异常；仅凭故障模块名也不能认定是内存溢出、显卡驱动或某一行应用代码。[Microsoft NTSTATUS 文档](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-erref/596a1078-e883-4972-9bbc-49e60bebca55)

本轮读取到的 Android crash 缓冲区为空。应用历史退出原因主要为 `USER REQUESTED / REMOVE TASK / FORCE STOP`；没有在这些现存记录中看到应用 Java／native crash、ANR 或 LOW_MEMORY。日志会轮换，因此这不等于证明从未发生应用崩溃。

另一个可复现现象是自动化运行时画面不再推进。0.1.9 的诊断记录显示 Flutter 已请求下一帧而未收到，且没有保存错误；本轮默认 Medium Phone 又在第二组演示开始附近停止推进。这属于“停止出帧”的证据，不能与上述 Windows 进程崩溃混为一谈，也尚不能据此精确定位模拟器内部调用栈。

## 当前环境与可能影响

现有 Medium Phone 为 Emulator 36.6.11、Android 17／API 37、x86_64 Google Play 16 KB 镜像；配置为 GPU `auto`、4 核、2 GB RAM、Quick Boot。图形后端兼容、宿主系统组件和启动快照均是排查方向，现有证据不足以确定其中哪一项触发了 COM fail-fast。

Android 官方说明，不兼容的图形加速选项可能导致模拟器崩溃或显示异常，图形问题可用软件后端做对照。但这只是排查方法，不能据此把本次 `combase.dll` 故障归因给 GPU。[Android 图形加速说明](https://developer.android.com/studio/run/emulator-acceleration)

## 与本轮应用修复的关系

应用自动保存原先会在 UI isolate 中完成整个累积记录的统计、规范 JSON、校验和行编码，第二组还会重复计算已封存组的摘要。这些同步工作会竞争动画和节拍调度时间，本轮已将 S2／M1 的计算移到后台，并缓存已封存组摘要。这是应用内的卡顿改进，不宣称它修复了 Windows 模拟器进程的 COM 崩溃。

真机进一步定位到原生代码逐音在主线程重复申请焦点，已改独立音频线程并复用焦点。真机 M1 的 16 秒演示录屏最大进度更新间隔由 249.1 ms 降至 54.2 ms。模拟器不能稳定出帧，因此未用它的计时结果评价这项修复。

## 建议的后续定位顺序（未对现有模拟器执行）

1. 同一镜像的独立测试实例做冷启动／软件图形对照，保留原实例配置和练习数据。本轮测试使用独立临时实例；同时启动只读原 AVD 的尝试被 Emulator 拒绝，随后创建了相同设备规格与镜像的临时测试 AVD。
2. 若宿主模拟器进程再次退出，应保存该时间点的 WER minidump，用调试器取得调用栈，才能进一步定位 `combase.dll` 内的具体触发链。
3. 如需确定是否与 API 37 镜像相关，再用独立稳定镜像做相同操作对照；不要用清空现有 AVD 数据代替定位。

原始证据：[Windows 事件](medium-phone-windows-0.1.10.log)、[Android 退出记录](medium-phone-exit-info-0.1.10.log)、[crash 缓冲区](medium-phone-crash-0.1.10.log)、[本轮停止出帧日志](phrase-0.1.10-default-renderer-stall.log)。

临时测试 AVD 同样未稳定启动，已停止并删除，仅保留原 Medium Phone。真机的 Flutter 调试自动化因 Vivo 关闭系统日志而不能发现 VM service；`setprop` 被系统拒绝，原值仍为 `no`。TalkBack 的诊断模式不是 ADB 日志开关，无需为此开启无障碍服务。随后使用用户授权的独立 release 测试包手动操作和录屏验证，不再修改系统诊断设置。
