# 0.1.68 三门课程与短信登录联调包

日期：2026-11-13。基于最新 main d37230a，包含队友短信登录/绑定提交和 e032966 播放缓冲修复。中文与英文界面均可自主选择新平衡舞步六式（3段）、Brain and Body（4段）、Move and Shout（3段）。Fandango 已移出当前课程与安装包，历史训练记录仍可读取。

## 安装包

[下载 ARM64 联调 APK](https://ccqspace.site/pd-rehab/assets/app-releases/0.1.68/PianoForParkinson-0.1.68-media-sms-QA-arm64.apk)。包名 `.validation`，版本 0.1.68+69，开发签名沿用上个联调包，不覆盖另一证书签名的正式 App；无 GitHub Release。

大小 124,882,291 字节（约119.10 MiB），较上一 ARM64 QA 包减少344,314,036字节（73.384%）。SHA-256：`7346f873278f74bdf9d06bf502ae9058de1d5c4436bf5afceaaf3d31694f8b25`。APK签名验证通过，内部十段资源清单与canonical一致，未打包任何 MP4/WebM。十段视频全部从服务器播放、按实际读取缓存，旧中文v1缓存身份保留。

## 自动化

Flutter836通过、2项原有opt-in联网测试跳过；短信界面26通过；原生106通过、无失败/跳过；静态检查无问题。具体测试见[功能验证](media-courses-sms-20261113.md)。所有真实素材均HEVC，目标Android的实际解码、弱网/中断及跨进程缓存仍待真机验收，本机未连接设备。

短信及Web部署已经完成真实验收：两次实际PNVS发码和正确验证码登录，首次/重复为同一用户与患者，挑战重放401、工作人员接口403、本人bootstrap200；只重启PD后端，旧24张业务表在迁移时完整保留。详细证据见 [Web交付记录](https://github.com/WuChangqing1/PD-Rehab-Web/blob/main/docs/media-sms-20261113/交付与验收.md)。不得把本机替身测试、providers开启或APK构建视为真实短信核验通过。AccessKey、手机号、验证码、Token和恢复码不得加入公开文档或Git。
