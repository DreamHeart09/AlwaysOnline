# Popover 视觉检查记录

本轮保留 340pt 宽度、原有横向控件和信息结构；检测、授权、事件发送和状态绑定未修改。统一浅深色 Surface / Accent / Radius / Shadow 参数，设置卡片移除重复 Material，增加细微高光；选中块增加柔和边缘和阴影。运行按钮保持品牌蓝。

## 已完成

- Swift 原生编译、应用签名验证、Info.plist 检查和 Git diff 空白检查。
- 代码审查；修正按钮白字对比。按钮正常/Hover 对比：浅色约 5.75/5.49:1，深色约 5.08/4.86:1。
- NSHostingView 原生离屏渲染四种状态，内容尺寸均为 340 × 435pt；检查后收敛暗色阴影、禁用态淡化和按钮渐变。
- 运行状态设置区禁用，保留 Button 无障碍语义、选中标记、左右键操作及 Reduce Motion。

## 四张图的性质与限制

此目录 PNG 是离屏布局检查图，不是真实菜单栏 Popover 截图，不能用于最终视觉验收或正式宣传。临时检查程序直接设置 running 展示状态，没有调用 start()，没有发送事件。检测/权限值来自构建环境，不能代表桌面设备实际状态。背景使用系统窗口底色，无法反映桌面透景与原生 Popover 材质。

| 外观 | 停止 | 运行 |
| --- | --- | --- |
| Light | [离屏图](light-stopped-offscreen.png) | [离屏图](light-running-offscreen.png) |
| Dark | [离屏图](dark-stopped-offscreen.png) | [离屏图](dark-running-offscreen.png) |

## 未完成的实机验收

桌面工具可以读取 Finder；按完整应用路径定位菜单栏应用多次超时，按 bundle ID 又遇到已安装、挂载磁盘和 dist 三份同 ID 应用。已尝试从 Finder 打开最新 dist 应用，仍无法取得 Popover 的窗口或状态树。因此尚未采集 Light/Dark × Stopped/Running 的真实截图。

仍须实机验证：卡片和桌面材质的融合、暗色边缘亮度和阴影、四种状态实际渲染、Hover/Pressed、键盘焦点/左右键/VoiceOver、开关面板与右键菜单。未将编译或离屏图当作最终验收。
