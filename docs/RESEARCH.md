# 技术调研（2026-10-30）

## 决策

目前优先验证 flagsChanged，鼠标微位移作为实验后备，电源断言独立配置。尚无可复现的企业微信真实状态证据，不进入产品实现。保活间隔 300 秒只是实验参数，不是企业微信阈值。

| 项目 / 方法 | 源码或证据 | 结论和局限 |
|---|---|---|
| [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) | 项目说明其封装 caffeinate；本次未完成底层源码审查 | 防休眠工具，用户多；不等于企业微信活跃。 |
| [WakeyWakey](https://github.com/brndnsvr/WakeyWakey) | 项目介绍和架构文档描述鼠标活动、调度和断言；本次未完成逐文件代码检查 | 有设计参考价值；企业微信状态未证实。 |
| [Bustelo](https://github.com/swlittles/Bustelo) | 作者报告不改变修饰状态的 flagsChanged、暂停条件与计时器对比；本次源码目录未能获取 | 候选无位移方案；作者报告不是本机或企业微信验收。 |
| [MouseKeepAlive](https://github.com/alpacachen/MouseKeepAlive/blob/main/MouseMonitor.swift) | 当前检索到的源码含键盘字符日志、全局监听和主屏内随机位置移动；与 README 描述的微位移往返不一致 | 针对企业 IM 的主张缺乏独立验收证据；隐私及多屏影响值得注意。源码和 README 可能随版本改变。 |
| [WeComKeepAlive](https://github.com/ZainZhao/WeComKeepAlive) | 指定地址本次无法获取 | 无法核实源码、维护或有效性，不与其他同名仓库混同。 |

公开搜索中 KeepingYouAwake 社区更大，但功能是防休眠；未发现有充分独立证据证明更活跃的原生项目稳定保持当前企业微信状态。查询和访问受限，不能断言不存在。

Apple [IOPMAssertionDeclareUserActivity](https://developer.apple.com/documentation/iokit/1557127-iopmassertiondeclareuseractivity) 说明它声明用户活动、唤醒显示器并延后显示器休眠，无需特殊权限；文档未承诺改变企业微信状态或 HIDIdleTime。`caffeinate -i` 与一般 idle system sleep assertion 不等价于用户输入；`-u` 则声明用户活动，应分别实验。CoreGraphics [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent) 提供投递 API，投递不返回成功状态；[Apple WWDC 2019](https://developer.apple.com/videos/play/wwdc2019/701/) 介绍合成事件所涉授权。辅助功能授权状态也不能证明实际投递及应用侧效果。

HIDIdleTime 是 IORegistry 指标，CGEventSource 可针对不同事件源及事件类型读取时间；这几种来源的更新机制、模拟事件污染及与企业微信的关系需本机实验，不能简单等同于“真实物理输入”。flagsChanged 仍会被其他应用观察，不能保证无副作用。鼠标事件有悬停、拖拽、边界和真实输入竞争风险。没有发现公开支持且已验证能直接保证第三方企业微信在线的系统 API。

## 正式产品准入

1. 重复 T1–T4，获得超过自然离开阈值的另一账号观察记录。
2. 验证锁屏、屏保、睡眠、显示器休眠、切换用户时绝不发事件；使用可靠事件与状态检查，不依赖本 PoC 的非公开字段。
3. 设计真实输入与自身合成事件的区分，并核验权限、焦点、双屏和鼠标按键竞态。
4. 若 flags 不影响企业微信但鼠标有效，手动选择鼠标后备；若都无效，不声称功能可用。
