# 计划插画、按钮图标及记录分类（2026-11-02）

- 七项钢琴练习共用的准备页“开始练习”加入播放图标；共用完成页“再练一次”“返回首页”加入重练、首页图标，沿用原按压动画和导航动作。
- 计划页使用39-plan-page-header作为页面背景，仍位于Scaffold body内，不覆盖底部导航。空状态使用38-plan-page-illustration。原PNG保留，新900像素WebP运行副本合计约211KiB，沿用现有assets/ui_images资源声明。
- 计划卡片根据dance、piece、exercise的training_id映射对应练习插画。背景位于文字和控件下层，图片半透明并叠加从左到右的浅色遮罩。背景和边框仍在同一个QinPress变换内，Switch继续使用QinPressBlock隔离卡片动画和长按；高对比度隐藏插画。
- 删除记录页“舞蹈记录”独立入口，舞蹈记录继续保留在统一最近记录列表中。
- 原“最近练习”位置替换为单选四分类：最近练习（全部）、钢琴练习（七项）、钢琴曲目、舞蹈训练。使用Wrap适配窄屏和大字号。
- 分类筛选保留全局时间排序与现有分页游标。若当前已加载页面没有匹配记录，继续加载直到找到匹配或到达末页；分类下的“加载更多”同样寻找后续匹配记录。切换分类可中止前一分类的查找，错误保留重试入口，不将尚未查完的分类误报为空。

验证：

- flutter analyze --no-pub通过。
- 计划交互、历史详情、曲目完成页和按压组件33项相关检查通过。
- 分类及详情专项9项通过，包括跨分页筛选、读取失败重试、空分类在大字号下结束查找、返回首页和只读历史详情。
- 七项钢琴练习完成页的28项中英文、大字号结果检查通过；M1准备预览等7项原有检查通过。
- 另8项旧M1训练中暂停测试仍因将QinOutlinedButton强制转为OutlinedButton而失败，位置为test/widgets/alternate_test.dart:151，未改动该处测试或训练中暂停逻辑。未声称全套测试通过。
- 日志：build/plan-art-and-history-categories-analyze.log、build/plan-art-and-history-categories-tests.log、build/history-categories-and-piano-icons-tests.log、build/history-categories-final-tests.log。

本轮更新源码和运行图片资源，未构建新APK。

## 顶部区域、悬浮新建入口及等宽分类

- 计划标题下增加“按自己的节奏，安排练习。”，标题区域与列表分开布局，窄窗口及大字号下可滚动标题内容。
- 移除列表内的大“新建计划”按钮，改为body底部居中的64dp圆形加号，距离body底边20dp，背景不透明度0.84。body位于导航栏上方；列表底部预留空间，最后一张卡片可滚动到按钮上方。批量选择时隐藏新建按钮。
- 记录分类改为“全部”；四个分类用Expanded均分一行。窄屏或大字号用“全部、练习、曲目、舞蹈”，英文使用简短标签；完整名称保留在提示中，必要时缩放标签以避免横向溢出。
- 视觉参数集中于lib/features/plans_page.dart文件顶部：planCardBackgroundOpacity控制整个卡片背景层、planCardImageOpacity仅控制训练插画、planCardImageAlignment控制cover裁切对齐、planHeaderBaseHeight控制标题基础高度。标题还会随字号增高，并限制在页面可用高度的40%以内。文字、按钮、开关不参与背景透明度。
- 静态检查、33项计划/记录/按压专项通过，包括圆形按钮居中和底部间距、新建页面导航、双倍字号下四分类同一行等宽、计划开关及批量操作。
- 日志：build/plan-floating-header-analyze.log、build/plan-floating-header-tests.log。
