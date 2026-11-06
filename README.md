# Always Online：菜单栏验证版

本项目已有最小 GUI，仍属于验证版，尚未证明能够让企业微信保持在线。

## 打开菜单栏 App

运行 `dist/Always Online.app`，在屏幕顶部菜单栏找到空心圆图标，点击打开面板。选择「无位移」和 30 秒测试间隔，授予辅助功能权限并点击刷新，然后开启。等待至少一次事件后，用另一账号观察企业微信状态；点击停止或退出会停止发送。也可以选择鼠标微位移，注意其可能影响悬停、拖拽和鼠标操作。默认间隔为 5 分钟。设置不持久化，退出后需重新开启。

如果辅助功能授权弹窗未出现，请打开「系统设置 → 隐私与安全性 → 辅助功能」，添加并启用 Always Online；重建后的临时签名可能需要删除旧条目后重新授权。应用无需付费开发者账号。

锁屏通知及会话检查尚未在本机图形会话验证，也使用非公开会话字段；**锁屏、切换用户、屏保或睡眠前请手动停止**。此版本不保证锁屏自动恢复，也不根据真实输入或企业微信运行状态控制发送，属于手动验证工具，不适合无人值守常驻。事件投递调用无成功返回值，显示已调用不表示投递生效或企业微信在线。

构建：`./scripts/build-app.sh`。应用本地临时签名，未经过 Apple 公证。当前受限执行环境无法启动图形界面，需在正常桌面中验证；如仍不能打开，请把系统错误告知我们。

---

# Always Online：实验阶段

这是用于研究 macOS 空闲计时与企业微信状态的实验程序，不是已验证的保活产品。**系统计时器归零不代表企业微信显示「在电脑前」。** 不读取聊天、剪贴板或键盘内容，不联网。请在本机终端中操作；默认只观察，不发送事件。

## 构建

需要 macOS、Swift 和 Command Line Tools；无需付费开发者账号。首次构建可能较慢：

```sh
mkdir -p /tmp/always-online-module-cache
swiftc -module-cache-path /tmp/always-online-module-cache Sources/main.swift -o always-online
./always-online --help
```

实验模式：`observe`（默认）、`power`（仅阻止空闲系统睡眠）、`user-activity`（声明用户活动）、`flags`（修饰键事件）、`mouse`（1 像素往返）。`--interval` 默认 300 秒，`--sample` 默认 5 秒，`--duration` 默认 0（直到 Ctrl-C）。间隔至少 2 秒，采样至少 1 秒；事件在启动后等待一个完整间隔才发送。关闭终端或 Ctrl-C 会终止实验。

```sh
./always-online --mode observe --duration 900 | tee observe.log
./always-online --mode flags --interval 300 --duration 1800 | tee flags.log
./always-online --mode mouse --interval 300 --duration 1800 | tee mouse.log
./always-online --mode power --duration 900 | tee power.log
./always-online --mode user-activity --interval 300 --duration 900 | tee user-activity.log
```

`flags` 和 `mouse` 检查辅助功能授权，缺失时跳过，不自动弹窗；需要在「系统设置 → 隐私与安全性 → 辅助功能」授权运行程序的终端或对应可执行程序，具体归属以系统显示为准。授权后重启实验；重建或更换终端可能需重新授权。系统管理员的限制可能影响授权。观察模式不要求该权限；程序不创建全局键盘监听。

**安全边界尚未验证：** 实验性的锁屏检查使用会话字典中的非公开锁屏字段，不能保证即时或可靠；请仅在解锁的本人会话中手动开展实验，锁屏测试之前先 Ctrl-C 停止事件模式。鼠标模式虽检查鼠标按钮和屏幕边界，仍有竞态，可能干扰拖拽、悬停或其他操作；不要在重要操作时运行。`CGEvent.post` 无返回值，日志 POST 仅表示调用，不证明系统接收。显示器休眠、屏保、快速用户切换等保护尚未充分实现，不适合作为后台常驻工具。

## 人工验证

使用第二个企业微信账号在另一台设备观察目标账号，记录目标账号客户端版本、网络、状态、开始和变化时间；不要从目标 Mac 操作查看结果。各组环境尽可能一致，每次从已知「在电脑前」开始，关闭其他防休眠或活动模拟工具，手机端行为保持一致。单组时间至少超过 T1 测出的自然离开阈值并留有余量。开启命令后手不触碰鼠标键盘。

1. T1：`observe`，测量从最后真实输入到对方看到离开的时间。
2. T2：`power`，观察防休眠与状态。该模式只阻止空闲系统睡眠，不保证屏幕常亮。
3. T3：`flags`，观察 BEFORE/AFTER 各计时器及另一账号看到的状态；记录异常快捷键、焦点或输入法变化。
4. T4：`mouse`，同样记录计时器与状态，分别在两个显示器和边缘附近测试，留意悬停和鼠标漂移。
5. T5：暂不开展自动锁屏事件测试；锁屏前退出实验。可靠锁屏暂停机制需要先实现并验证。
6. 如需区分 `caffeinate`：另行使用系统 `caffeinate -i` 配合 `observe`，结束时 Ctrl-C；这与 `caffeinate -u` 的用户活动声明不同。

记录模板在 [docs/TEST-RECORD.md](docs/TEST-RECORD.md)。日志使用 UTC 时间（结尾 Z），企业微信状态必须人工标注本地时间或换算。每项分开记录：API 创建/调用，系统计时变化，企业微信真实状态；未知填「未验证」。

HIDIdleTime 及 CGEventSource combined-session 是不同来源的计数，不可保证其中任何一个仅反映物理输入。模拟事件可能污染其中某些计时器，不能用它直接构建“真实用户正在操作”的判定。

当前程序不采样 CGEventSource 的 HID 和 private 状态：在本次执行环境中调用出现阻塞。combined-session 在本次环境中始终返回 0，不能据此判断实际空闲；需在用户终端中重新验证。
