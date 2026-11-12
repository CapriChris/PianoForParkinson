# 舞蹈视频资源

0.1.67 联调版中，中文《新平衡舞步六式》三部分使用 HTTPS 在线播放及 Android 播放缓存，不再随 APK 打包。资源地址、长度、版本及 SHA-256 随应用打包于 [remote_manifest.json](remote_manifest.json)。进入课程只读取当前片段，不下载其他片段；完整字节经过本地 SHA-256 验证后才可离线播放，部分缓存仍可能需要联网。

英文 Fandango 尚未托管，继续使用随包的 `fandango-lesson-4.webm`。首次克隆后，从 [v0.1.56 Release](https://github.com/CapriChris/PianoForParkinson/releases/tag/v0.1.56) 下载通用 APK，在仓库根目录执行：

```powershell
python tools/prepare_dance_asset.py --from-apk C:/Downloads/qinban-0.1.56-android-universal.apk
python tools/prepare_dance_asset.py --check
flutter pub get
```

默认只恢复和校验当前随包的视频。若需要归档原来的三段 MP4，可加 `--include-remote`；这不是构建要求。脚本不转码，不覆盖不匹配的已有文件。[manifest.json](manifest.json) 保留四个原始播放文件的校验信息，二进制不提交 Git。

- 中文素材由项目团队提供，来源及再分发授权沿用原权利人说明。
- 英文：RIDC NeuroMat，Bora Dançar com Parkinson: Módulo Fandango (aula 4)，原片未修改，[来源](https://commons.wikimedia.org/wiki/File:Bora_Dan%C3%A7ar_com_Parkinson-_M%C3%B3dulo_Fandango_(aula_4).webm)，[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)。

课程及分段 ID、训练记录、计划和关于页的素材来源均保持原有含义。缓存保存在 App 私有、不参与备份的目录中，容量上限 1 GiB；内容可被空间压力或 LRU 淘汰，不能作为永久保存副本。
