# 舞蹈视频资源

0.1.68 起，中英文界面均提供三门课程：新平衡舞步六式 / New Balance Six（3部分，中文视频）、身心协调 / Brain and Body（4部分，英语视频）、律动与发声 / Move and Shout（3部分，英语视频）。选择课程不依赖界面语言。十段都使用 HTTPS 在线播放及 Android 播放缓存，构建无需下载或恢复任何视频二进制。

[remote_manifest.json](remote_manifest.json) 为随包资源清单，schemaVersion=1、resourceVersion=v2。中文三段保持既有 courseId、partId、v1 URL、长度和 SHA-256；英文七段使用 v2 不可变路径。三张海报由对应视频取帧，地址也列于清单。素材由项目团队提供，来源和再分发权限以原权利人许可为准。

播放器仅按需读取当前选中分段；没有整段下载按钮、后台下载任务或其他分段预取。缓存位于 Android 私有 noBackup 目录，上限 1 GiB，保留 LRU、活动文件保护及可用空间预算。完整本地字节通过 SHA-256 校验后才报告可离线播放；部分缓存仍可能需要联网。网络和缓存失败可重试，未产生有效播放时不计入训练时长。

[manifest.json](manifest.json) 及恢复脚本仅用于旧资源归档，不是当前构建依赖。旧课程历史、结果、已有计划与数据库均保留，不清理旧记录。目标 Android 手机仍须验证 HEVC 解码、弱网、跨进程离线缓存及中断恢复。
