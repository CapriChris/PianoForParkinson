# 琴伴 0.1.15 构建记录

日期：2026-10-17。版本：0.1.15+16。

本次用户明确要求无需测试，因此没有运行单元、界面、集成、手工、性能测试或静态分析；没有沿用旧版本的测试通过数。本次只修改代码、格式化、生成 release 包并覆盖安装，没有启动应用进行流程验收。

## 修改

- 首次左右触点且原生确认双触点后，将完成标记保存到已有本地设置；保存成功后才可继续。后续所有 M2 入口及正式开始接受此标记，应用重启后无需再检查。
- 修正 M2 每组开始时的提示：waiting 为“即将开始”，countdown 显示现有引擎的 3、2、1，结束后显示目标双键；去掉“松开后继续”。
- 提示改为“同时按下两琴键”，并使用旋律记忆相同的组／项编号格式。

## 构建与安装

首次 `flutter build apk --release --no-pub` 因旧集成测试残留的插件注册引用而编译失败，日志为 `m2-first-check-0.1.15-release-build.log`。改用正常 `flutter build apk --release` 重新生成依赖／插件注册文件后成功，日志为 `m2-first-check-0.1.15-release-build-retry.log`。没有运行测试来解决此构建问题。

`adb install -r` 返回 Success，覆盖当前 emulator-5554 中同包名应用；安装后的包信息为 versionName 0.1.15、versionCode 16。安装日志为 `m2-first-check-0.1.15-install.log`。

- 包名：`com.pianoforparkinson.piano_practice`
- 安装包：`releases/琴伴-0.1.15-internal.apk`
- 大小：55,807,627 字节
- SHA-256：`a207ad27e8f647c370c7c0b0110c867abc37db1df6d3bae09c7a5b971315e716`

本版没有更新截图，也没有完成真实双指或界面流程验收。旧版已知的 M1 模拟器出帧问题不在本次修改范围内。
