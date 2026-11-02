# CausalNet 本地检查

`inspect_causalnet.py` 使用本地可信权重，以 `weights_only=True`、CPU、内存映射方式读取。需要 Python 3.11+、PyTorch、einops。不会启动训练、摄像头或上传数据，也不会修改模型目录。

示例：

```powershell
python tools/model_validation/inspect_causalnet.py --model-dir ../CausalNet-main --output validation/causalnet-smoke.json
```

输出包括文件清单、网络深度推断、保存的位置矩阵对应的 gamma、参数量、严格加载检查及单条零张量输入的输出形状、有限值检查和桌面耗时。仅首个权重执行严格加载和推理，其余权重对比键及形状、读取位置矩阵；不能声称所有权重均已逐个推理。

2026-10-31 本地结果：九份权重均为 (3,3,7)，与 eval.py 的 (3,3,9) 不同。010、012、013、s01、s06 的位置矩阵对应 gamma=0.4；s12、sub01、sub08、sub22 对应 0.3。当前 forward 使用已加载的矩阵缓冲，初始化 gamma 不应被误认为权重来源证明。模型约 224,704,521 个参数。010.pth 严格加载及合成输入检查通过，输出 [1,3] 且有限。

这些结果仅验证工程兼容性，不是准确率、患者适用性或手机端性能评估。后续需要原始视频到特征的生成过程、连续视频事件标注／检测、受试者划分及训练数据和权重许可；在这些条件明确前，不在应用中启用摄像头或展示微表情评价。
