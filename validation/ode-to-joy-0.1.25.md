# 欢乐颂主题简化版验证

日期：2026-10-22（北京时间）。版本：0.1.25+26。

## 自动化检查

`flutter test test/data/content_test.dart test/data/ode_to_joy_test.dart test/widgets/song_library_test.dart --reporter expanded`：13 项通过。日志：ode-to-joy-tests-0.1.25.log。

- 原曲目与音频资源哈希、界限及许可信息校验通过。
- 《欢乐颂》前两句主题按正确音高顺序加载，共 30 音；只出现在 S1 曲库。
- 手动时钟运行完整训练，两个完整 30 音示范、暂停恢复、60 项完成与进度分母正确；通过 RecordContract.validate，未写用户数据库。
- 实际曲库和说明页组件覆盖中文／英文、360×640／800×360、正常／双倍字号，选曲设置正确保存到内存存储替身，页面无布局异常。大字号页面按设计滚动访问。
- S2 曲库仅展示兼容的八音条目。

`flutter analyze --no-pub`：通过，无问题。日志：ode-to-joy-analyze-0.1.25.log。

## 构建与安装

`flutter build apk --release`：通过，Gradle 20.3 秒，APK 约 54.1 MB。日志：ode-to-joy-build-0.1.25.log。首轮使用 --no-pub 的构建遇到旧 GeneratedPluginRegistrant 引用 integration_test 的错误，正常构建重新生成插件注册后通过，无手工修改生成文件。

构建产物复制为 releases/琴伴-0.1.25-internal.apk，与原始 APK 的 SHA-256 一致。`adb -s emulator-5554 install -r` 成功，包信息确认 versionName=0.1.25、versionCode=26。未卸载或清空应用数据，未向已连接真机安装。

## 设备页面核对

模拟器启动后从练习目录打开短旋律练习，核对《欢乐颂》优先显示、贝多芬与五键／30 音说明；选曲进入说明页。已查看以下截图，无裁切或重叠：

- screenshots/ode-to-joy-0.1.25/01-library.png
- screenshots/ode-to-joy-0.1.25/02-instruction.png

检查时将模拟器应用语言切换为中文，并选择《欢乐颂》。未在用户安装中由代理开始正式训练；实际声音、输入延迟和设备端完整弹奏尚未验收，不能将手动时钟测试视为这部分通过。

## 适配边界

本版为前两句主题的逐音练习，统一按住 400 ms；没有原谱附点与长音、和弦或双手版本。内容与引擎边界检查没有放宽五键和时值要求。旧曲目哈希、任务参数、计分、数据库及既有封存记录保持。
