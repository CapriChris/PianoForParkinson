# 琴伴 Shorebird 自动补丁更新接入

## 本轮范围

基线为队友 feature/android-apk-updates 的 98a122f，独立分支 codex/app-shorebird-auto-update-20261120。原有完整 APK 更新器保留；本轮新增 Shorebird Dart 补丁能力，不改变患者记录、账号、训练算法、自动同步和数据库。

## 网络和账号复核

2026-11-19 的 CLI 日志保留登录成功及 auth status 成功记录。2026-11-20 直连诊断失败；仅为当前进程带上本机既有 HTTP/HTTPS 代理后，auth status 与 apps list 均成功，凭据自动续期，无需重新登录。没有修改 Windows 全局代理、没有将认证凭据写入仓库。代理属于开发电脑访问条件，患者联网可用性须在医院实测。

账号最初 apps list 为空，故本轮只创建一次“琴伴 PianoForParkinson”项目。真实 app_id 为 c48c2f0d-2b04-41b4-b46d-12613bd92b13，保存在公开 shorebird.yaml，auto_update:true。app_id 不是密钥。CLI 本次版本1.6.144；构建明确固定 Flutter3.47.7，避免工具默认最新版引擎导致未经评估的迁移。

## 患者使用

1. 保留原 App，使用相同包名与原证书覆盖安装一次包含 Shorebird 的基础 APK，不卸载、不清空数据。
2. 以后启动 App 时引擎后台检查并下载适配当前基础版本的补丁。离线仍可使用当前版本；下次完整启动进程才会运行已准备好的补丁。
3. “设置 → 关于本版本 → 检查热更新”可手动检查；下载不提供虚构百分比。检查/下载失败可稍后重试，训练不被重启或阻断。
4. 页面显示“下次启动生效”后，先完成训练、录像及同步，再正常退出重开。仅切后台再切回不保证进程已重启。
5. 原“检查更新”保留为完整安装包升级，用于原生插件、权限、引擎和内置资源变更。普通旧 APK 本身没有 Shorebird 引擎，不能仅靠服务端配置获得热更新能力。

## 原签名与候选版本

包名保持 com.pianoforparkinson.piano_practice。候选版本0.1.74+75，应用上报版本/构建号同步。android/key.properties 是本机忽略文件，明确引用用户交接的原密钥；不使用构建机自动生成的默认 debug 密钥，不生成替代证书。原密钥证书 SHA256 为69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca。release缺少签名配置时直接停止构建。

签名文件、密码、Shorebird登录凭据、私有测试库、安装包本体不提交 Git。实际 APK 的签名、字节摘要、包名及构建号必须在构建后再次核对。

## 发布和回滚边界

本轮只执行 shorebird release android --artifact apk --flutter-version 3.47.7 --dry-run 构建校验。dry-run不等于已上传基础Release，候选APK也不等于已发布或已验收。没有向stable发布补丁，没有替换生产服务器下载，没有合并main。

正式发布前：维护者协调合并并固定源码SHA；用同一签名、同一工具链创建实际Release；登记原始APK SHA256；先用staging/preview验证小幅Dart界面变更的下载与下次冷启动生效、离线/重试、会话/本机记录/同步保持、训练期间不强制重启，再批准stable。补丁针对明确基础版本，不能混用其他引擎、签名或构建产物。

回退补丁需在Shorebird撤回目标补丁，设备联网检查后按官方机制在后续启动使用上一补丁/基础代码。对已写入本机数据的格式变更必须保证向后兼容；原生或内置资源升级仍走新APK。没有通过卸载、清库或生产回滚冒充验收。

## 验证记录

静态分析无问题；完整Flutter测试919通过、2个默认opt-in跳过。8项新增热更新部件测试覆盖普通APK不支持补丁、下载后等待冷启动、离线异常、竞争下载不误报、当前版本状态、英文待重启状态、相同补丁不误报、重复点击与退出页面。

Shorebird dry-run完整AAB/APK构建校验通过，实际APK包名与构建号正确，未开启debuggable。新APK和实际下载的队友0.1.73 APK签名证书一致，均匹配原密钥指纹。实际Gradle聚合assemble在未配置签名时拒绝构建，debug-only task graph不要求发布密钥，避免绕过检查误产出未签名发布包。

首轮问题已定位：开发命令需沿用昨日已登录的本机代理；Gradle JVM也需单独携带代理。旧generated plugin registrant曾混入integration_test，改用完整release依赖生成流程解决。隔离SDK命令行工具采用非标准嵌套目录，增加latest目录指向既有工具后，apkanalyzer校验通过；未绕过或删除构建校验。

Pad OPD2506已连接；原正式包名此前未安装，既有.validation测试包保留。正在通过旧正式APK创建升级对照，安装授权需由设备持有人在Pad自行完成。随后才可登记用于设备联调的基础Release及staging补丁，不能将当前源码/构建通过等同于真机补丁已生效。

## 官方依据

[更新下载与生效](https://docs.shorebird.dev/code-push/how-devices-get-patches/)

[更新策略](https://docs.shorebird.dev/code-push/update-strategies/)

[创建基础版本](https://docs.shorebird.dev/code-push/release/)

[能力限制](https://docs.shorebird.dev/code-push/faq/)
