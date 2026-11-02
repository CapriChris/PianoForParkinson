# 0.1.56+57 发布构建与验证

日期：2026-11-02（北京时间）。发布类型：内部测试版/GitHub Pre-release。

## 构建

主包：`flutter build apk --release --target=lib/main.dart`。

预览版升级包：追加 `--dart-define=ISOLATED_TEST_PACKAGE=true`。两次构建均成功，主入口均为lib/main.dart，未混入集成测试入口。

| 项目 | 结果 |
| --- | --- |
| 应用版本/构建号 | 0.1.56 / 57 |
| 最低/目标Android API | 24 / 36 |
| 架构 | armeabi-v7a、arm64-v8a、x86_64 |
| 主包 | com.pianoforparkinson.piano_practice，659372452字节，约628.8MiB |
| 旧预览版升级包 | com.pianoforparkinson.piano_practice.validation，659372460字节，约628.8MiB |
| 签名 | 沿用开发签名，与已有预览包证书相同；不是商店正式签名 |
| 证书SHA-256 | 69d255082293ffe1f72f35cea68e57ea4a0edf3917fe07b97de88b0f40a102ca |
| 权限 | POST_NOTIFICATIONS、SCHEDULE_EXACT_ALARM、RECEIVE_BOOT_COMPLETED；未声明CAMERA或INTERNET |
| 离线视频 | APK恰好包含四个播放副本，共564458700字节；逐个与资源清单校验大小和SHA-256通过 |

APK SHA-256：

```text
5d6ee5d6059ec9573a221694027c26f502ae7a7adbc3a5abea0465499934c552  qinban-0.1.56-android-universal.apk
393188df9716b9cef83fb48d099471fd236aae14fc5759dca15fee7a220a2721  qinban-0.1.56-android-universal-preview-update.apk
```

## 检查范围

- flutter analyze --no-pub：无问题。
- 本轮完整flutter test：606项通过、102项失败，退出码1。未宣称全套通过；失败清单见[完整列表](release-0.1.56-failing-tests.md)。与本地保存的历史基线比较，失败名称52项重合、50项不重合；不能把102项全部归为历史遗留。
- 近期功能专项103项全部通过：计划数据与迁移、排序/到期/自动进度、批量栏与目标输入、分类分页、舞蹈播放/保存/历史详情、通知权限/时区、按压、字号、速度记忆、谱面缓存及七项练习结果布局。
- 完整套件失败包含控件包装类型断言、按压动画后动作时序与旧界面查找断言，也包含既有夹具/状态问题；未在本轮逐项修复或证明全部只是测试适配问题。因此以Pre-release分发。
- 素材恢复脚本以独立临时夹具验证：从APK提取、大小与哈希验证、重复运行、不覆盖不匹配文件。APK真实视频成员另已全部校验。
- 本轮未安装到用户手机、未卸载已有应用或创建模拟器。此前曾在独立测试包上验证Android后台定时通知；这不代表本包已完成各品牌真机验证。

## Git与交付

仓库根是原工作区的app目录。代码、资源清单、插画、测试及文档提交Git；视频大文件、APK、数据库、签名密钥和本地构建日志不提交。

四个视频可以从任一新版Release APK恢复，脚本验证后才写入；无需Git LFS，也不在应用运行时依赖网络。Release提供两个APK、SHA256SUMS.txt和build-report-0.1.56.json。

当前模型检查脚本保留为开发工具；模型权重、摄像头、微表情端侧运行与AI指导未随本版接入。安装包仍为内部演示，不表示专业训练参数或患者适用性已经评审。

本地日志：build/release-0.1.56-analyze.log、build/release-0.1.56-tests.log、build/release-0.1.56-targeted-tests.log、build/release-0.1.56-main-build.log、build/release-0.1.56-preview-build.log。
