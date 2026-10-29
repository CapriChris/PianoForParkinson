# 琴伴 0.1.53+54 构建验证

日期：2026-10-28。应用包名为 `com.pianoforparkinson.piano_practice`；内部演示 APK 使用项目现有 Android Debug 签名。

- `flutter analyze`：通过，无问题。
- 引导页在 320、412 逻辑像素宽及 1×、2× 字号下的现有布局测试：4 项通过。
- 字号设置与曲目速度记忆相关测试：7 项通过。
- `flutter build apk --release`：构建成功。
- APK 元数据：versionName `0.1.53`、versionCode `54`、minSdk `24`；签名验证通过，证书为 Android Debug。
- 交付文件：[琴伴-0.1.53-internal.apk](../../releases/琴伴-0.1.53-internal.apk)，88,522,776 字节，SHA-256 `41A64778F6197C39B1CBA16E0E2BE2B778801072C577CFDAF8BBA8BC0EB539AD`；交付文件与构建输出的哈希一致。

本次未运行完整测试套件，未安装此 release 包至模拟器或真机，也未对最终构建进行设备视觉和音频验收。此前引导页设计曾使用独立调试副本检查；最后的文案和按钮顺序调整未单独截图验收。
