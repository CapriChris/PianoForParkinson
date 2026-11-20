# Shorebird 自动补丁接入与验证计划

已确认方案：患者安装一次原包名、原签名的 Shorebird 基础 APK，之后 Dart 补丁后台下载，下次冷启动生效。保留队友完整 APK 更新作为原生能力/资源/引擎升级入口；不强制重启，不修改训练、账号、数据库和同步。既有生产发布审批继续有效。

基础：origin/feature/android-apk-updates 98a122f，独立分支 codex/app-shorebird-auto-update-20261120。上轮 docs-only 分支和 Web PR 不受修改。账号登录已于 2026-11-20 经已有本机代理重新验证，未读取或复制令牌；账号当前无应用。

1. [ ] 创建唯一 Shorebird 项目并生成真实 app_id/配置，默认自动检查保留。不创建重复项目，不更换包名。
2. [ ] 先加入热更新面板回归测试并确认失败；实现关于页补丁状态、下载和真实下一次补丁状态检查。保留原 APK 面板。普通 Flutter 包明确不支持补丁。
3. [ ] 原签名从私有 android/key.properties 显式读取，正式构建缺失时停止。原证书 SHA256=69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca；密码/密钥不进入 Git。沿用 SDK，若不可用先报告，不能隐式升级。
4. [ ] Flutter analyze、热更新/完整 APK/账号/训练相关及全套测试；Shorebird dry-run 构建，核对 APK 实际包名/版本/签名/debuggable/更新器。
5. [ ] 连接设备时才验证原版覆盖安装、数据保留、补丁下载和冷启动；未连接则明确记录未验证。没有获准前不向 stable 发布补丁或将正式 APK 提供给患者。
6. [ ] 补齐实际日志、复现方法、回滚边界及独立分支交接，按既有分支协作不合 main、不部署生产。

文件：shorebird.yaml/pubspec.yaml/lock（官方依赖和项目配置）；android/app/build.gradle.kts（显式原签名）；lib/features/shorebird_update_panel.dart（关于页手动核验）；lib/app/piano_app.dart（插入面板）；test/shorebird_update_panel_test.dart（错误/并发/无真实补丁/普通包回归）。日志保留在 Git 外的 QA 目录。
