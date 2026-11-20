# Shorebird 接入与设备验收记录 2026-11-20

基线98a122f，基础实现2f793d0，Patch1源码5e5984b。独立分支codex/app-shorebird-auto-update-20261120。

| 检查 | 实际结果 |
|---|---|
| 既有登录与网络 | 使用原有本机代理后auth status成功，复用原账号；没有重新登录或输出凭据 |
| 原证书与0.1.73实包 | 指纹相同，69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca |
| 静态分析 | No issues found |
| 完整Flutter测试 | 919通过、2个默认opt-in跳过、0失败；最后一轮覆盖Patch1提示文字 |
| 部件测试 | 新增8项；提示文字回归先失败后通过 |
| dry-run AAB与APK | 成功，原包名，versionCode75，0.1.74，非debuggable |
| 缺密钥aggregate assemble | 实际拒绝并报告签名配置缺失 |
| 缺密钥debug-only task graph | 实际通过 |
| 独立源码审查 | 聚合构建签名边界已修复，复审无剩余可操作发现 |
| Shorebird基础登记 | Release0.1.74+75，ID999183，Android active，managed patch signing |
| 补丁登记 | Patch1，ID825530，仅staging；arm24430字节、arm6423862字节、x86_6423937字节 |
| 正式stable | 未发布补丁；未更新Web生产下载清单、未合并main、未部署服务器 |
| Pad | OPD2506已连接；旧.validation包保留。普通正式包安装正在等待设备持有人完成系统锁屏密码确认 |
| 覆盖后数据保留 | 尚未验证，不能宣布通过 |
| 自动下载与冷启动生效 | 尚未验证，不能宣布通过 |

基础APK SHA256 f615ddaf189105d43102e4db5a13fdad9b9528f74c4cdcb1c8afb930a4c20b38；staging预览APK SHA256 52c5b802aa63d1cad5ddc2ac505f83435ef229c480c16c5b9620b8ab5ac05536。两者使用相同原证书，预览仅调整官方channel配置，不作为正式分发包。

原始日志保留本机私有QA目录，不上传认证文件、密钥、密码、APK或数据库。以下哈希用于对应真实执行记录，自动化结果不等同于真机已通过。

| 日志 | SHA256 |
|---|---|
| analyze.log | 0d45241499f02a16fe03e97fd1c45943dd3ffc1694622490144109dae3f72ec3 |
| flutter-test.log | a893e0193f1890a890d1697b9a4b9ab5be3c090f8960495781feeeba58ea703c |
| release-dry-run.log | 4080a0a3d8b1f7a2662cedf023315a70a037333144d091dbf84bf2353f5762dd |
| release-register.log | d70fd8d9e63b7460d0a41e17b33f951c6b3e3a28cf5c6222e39e2e7a6b7c4487 |
| patch-staging.log | c9e443d40f34254828992f61d3028d21e67bb7f98d04ac9bee28c46131162dcc |
| signing-missing-aggregate.log | 6c63308cdf760f11f8dfcfc969e96a348283ed14731b59d3e82d14b4fadf0347 |
| signing-debug-no-key.log | fbd116fb35f33d863255bd68eab98c30520631e3dc3990283786d03402ab8fb0 |
| reference-certificate.log | e4f69275539e58e315580afbf50ee7668f75422f4e7d147fa888866f5b31b272 |
| preview-certificate.log | e4f69275539e58e315580afbf50ee7668f75422f4e7d147fa888866f5b31b272 |
