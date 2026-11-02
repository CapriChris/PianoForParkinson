# 离线舞蹈视频

应用打包四个离线视频，完整文件清单、字节数及SHA-256见 [manifest.json](manifest.json)。视频二进制不进入Git历史，避免重复原片及超过GitHub单文件限制；Release APK内包含完整播放副本。

首次克隆仓库后，从 [v0.1.56 Release](https://github.com/CapriChris/PianoForParkinson/releases/tag/v0.1.56) 下载通用APK，在仓库根目录执行：

```powershell
python tools/prepare_dance_asset.py --from-apk C:/Downloads/qinban-0.1.56-android-universal.apk
python tools/prepare_dance_asset.py --check
flutter pub get
```

脚本仅提取清单中的四个文件，校验后原子写入，不覆盖不匹配的已有文件。也可先放入团队提供的第一、第二、第三部分原始MP4及唯一的Bora_*.webm，再运行不带参数的脚本生成ASCII播放副本；原始文件不会删除。

- 中文：新平衡舞步六式第一、第二、第三部分，素材来源及授权沿用课程原权利人说明。
- 英文：RIDC NeuroMat，Bora Dançar com Parkinson: Módulo Fandango (aula 4)，原视频未修改，[来源](https://commons.wikimedia.org/wiki/File:Bora_Dan%C3%A7ar_com_Parkinson-_M%C3%B3dulo_Fandango_(aula_4).webm)，[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)。

App内的“关于本版本”保留课程来源及许可说明。恢复素材用于从源码构建，不改变App离线播放方式。
