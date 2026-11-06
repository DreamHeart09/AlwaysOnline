import SwiftUI
import AppKit
import ApplicationServices
import IOKit
import Combine

private func templateImage(_ image: NSImage) -> NSImage {
    image.isTemplate = true
    return image
}

private let menuBarBrandImage: NSImage? = {
    guard let url = Bundle.main.url(forResource: "AlwaysOnline-MenuBar", withExtension: "png"),
          let image = NSImage(contentsOf: url) else { return nil }
    return templateImage(image)
}()

@MainActor final class Engine: ObservableObject {
    @Published var running = false
    @Published var mode = "无位移"
    @Published var interval = 300.0
    @Published var status = "已停止"
    @Published var trusted = AXIsProcessTrusted()
    @Published var last = "尚未发送"
    @Published var wecom = "未检测"
    private var timer: Timer?
    private var panelRefreshTimer: Timer?
    private var locked = false
    private var observers: [NSObjectProtocol] = []
    init() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.locked = true; self?.stop("锁屏，已停止；解锁后请手动开启") } })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.locked = false } })
        refresh()
    }
    func refresh() {
        let wasTrusted = trusted
        trusted = AXIsProcessTrusted()
        if trusted && !wasTrusted && status.hasPrefix("请在系统设置中授权") {
            status = "已授权，可以开始运行"
        }
        let matches = NSWorkspace.shared.runningApplications.filter { app in
            let name = (app.localizedName ?? "").lowercased(), id = (app.bundleIdentifier ?? "").lowercased()
            return name.contains("企业微信") || name.contains("wecom") || id.contains("wxwork") || id.contains("wework")
        }
        wecom = matches.isEmpty ? "未检测到（可能漏报）" : "已检测到"
    }
    func beginPanelRefresh() {
        refresh()
        panelRefreshTimer?.invalidate()
        let refreshTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        panelRefreshTimer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
    }
    func endPanelRefresh() {
        panelRefreshTimer?.invalidate()
        panelRefreshTimer = nil
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        status = "请在系统设置中授权 Always Online，然后重新打开此面板"
    }
    func start() {
        refresh()
        guard trusted else { status = "需要辅助功能权限"; return }
        guard !locked else { status = "屏幕已锁定"; return }
        running = true
        status = "运行中：首次事件将在间隔后发送"
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.send() } }
    }
    func stop(_ reason: String = "已停止") { timer?.invalidate(); timer = nil; running = false; status = reason }
    func send() {
        guard running else { return }
        refresh()
        guard trusted else { stop("权限已失效，已停止"); return }
        guard !locked, let session = CGSessionCopyCurrentDictionary() as? [String: Any], (session[kCGSessionOnConsoleKey as String] as? Bool) == true, (session["CGSSessionScreenIsLocked"] as? Bool) != true else { stop("会话不可用或锁定，已停止"); return }
        guard !CGEventSource.buttonState(.combinedSessionState, button: .left), !CGEventSource.buttonState(.combinedSessionState, button: .right), !CGEventSource.buttonState(.combinedSessionState, button: .center) else { last = "跳过：鼠标按钮按下"; return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty else { last = "跳过：修饰键按下"; return }
        if mode == "无位移" {
            guard let event = CGEvent(source: nil) else { last = "事件创建失败"; return }
            event.type = .flagsChanged; event.flags = flags; event.post(tap: .cghidEventTap)
        } else {
            guard let pos = CGEvent(source: nil)?.location else { last = "无法获取鼠标位置"; return }
            var ids = [CGDirectDisplayID](repeating: 0, count: 32), count: CGDisplayCount = 0
            guard CGGetActiveDisplayList(32, &ids, &count) == .success, let rect = ids.prefix(Int(count)).map({ CGDisplayBounds($0) }).first(where: { $0.contains(pos) }) else { last = "无法确定鼠标所在屏幕"; return }
            let target = CGPoint(x: pos.x + (pos.x + 1 < rect.maxX ? 1 : -1), y: pos.y)
            guard rect.contains(target), let a = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left), let b = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pos, mouseButton: .left) else { last = "鼠标事件创建失败"; return }
            a.post(tap: .cghidEventTap); b.post(tap: .cghidEventTap)
        }
        last = "\(Date().formatted(date: .omitted, time: .standard)) 已调用事件投递（不代表在线）"
    }
}

struct ContentView: View {
    @ObservedObject var engine: Engine
    private let accent = Color.accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                if let image = menuBarBrandImage {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.primary)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "infinity")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Always Online")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 5) {
                        Image(systemName: engine.running ? "checkmark.circle.fill" : "pause.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(engine.running ? "运行中" : "已停止")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Text(engine.running ? "每 \(intervalLabel) 尝试维持活动状态" : stoppedDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                statusRow(icon: "message", title: "企业微信", value: engine.wecom == "已检测到" ? "已检测到" : engine.wecom)
                Divider().padding(.leading, 28)
                statusRow(
                    icon: "hand.raised",
                    title: "辅助功能",
                    value: engine.trusted ? "已授权" : "",
                    needsAttention: !engine.trusted,
                    actionTitle: engine.trusted ? nil : "开启权限",
                    action: engine.trusted ? nil : { engine.requestPermission() }
                )
            }
            .padding(.horizontal, 2)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 13) {
                Text("运行设置")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                segmentControl(title: "活动模式", values: ["无位移", "鼠标微移"], selection: Binding(
                    get: { engine.mode == "无位移" ? "无位移" : "鼠标微移" },
                    set: { engine.mode = $0 }
                ), disabled: engine.running)
                segmentControl(title: "发送间隔", values: ["1 分钟", "5 分钟", "10 分钟"], selection: Binding(
                    get: { engine.interval == 60 ? "1 分钟" : (engine.interval == 300 ? "5 分钟" : "10 分钟") },
                    set: { engine.interval = $0 == "1 分钟" ? 60 : ($0 == "5 分钟" ? 300 : 600) }
                ), disabled: engine.running)
            }
            .padding(13)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            .padding(.top, 14)

            Divider()
                .padding(.top, 14)
                .padding(.bottom, 11)
            HStack {
                Button { engine.running ? engine.stop() : engine.start() } label: {
                    Label(engine.running ? "停止" : "开始运行", systemImage: engine.running ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(accent)
                Menu {
                    Button("退出 Always Online", systemImage: "power") { engine.stop(); NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("更多操作")
            }
        }
        .padding(17)
        .frame(width: 340)
        .animation(.easeOut(duration: 0.2), value: engine.trusted)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: engine.running)
        .onAppear { engine.refresh() }
    }

    private var intervalLabel: String {
        engine.interval == 60 ? "1 分钟" : (engine.interval == 300 ? "5 分钟" : "10 分钟")
    }

    private var stoppedDetail: String {
        if !engine.trusted { return "需要辅助功能权限" }
        if engine.status == "已停止" { return "按需开始运行" }
        return engine.status
    }

    private func statusRow(
        icon: String,
        title: String,
        value: String,
        needsAttention: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 15)
            Text(title).font(.system(size: 12)).foregroundStyle(.primary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, systemImage: "arrow.up.right.square", action: action)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.link)
            } else if !needsAttention && (value == "已检测到" || value == "已授权") {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if !value.isEmpty {
                Text(value).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(needsAttention ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }

    private func segmentControl(title: String, values: [String], selection: Binding<String>, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(selection.wrappedValue).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
            }
            HStack(spacing: 3) {
                ForEach(values, id: \.self) { value in
                    Button { selection.wrappedValue = value } label: {
                        Text(value)
                            .font(.system(size: 11, weight: selection.wrappedValue == value ? .semibold : .regular))
                            .foregroundStyle(selection.wrappedValue == value ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                if selection.wrappedValue == value {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.wrappedValue == value ? .isSelected : [])
                    .disabled(disabled)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let engine = Engine()
    private var statusItem: NSStatusItem?
    private var statusDot: StatusDotView?
    private var popover: NSPopover?
    private var outsideClickMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 22)
        statusItem = item
        guard let button = item.button else { return }

        if let image = menuBarBrandImage?.copy() as? NSImage {
            image.isTemplate = true
            image.size = NSSize(width: 20, height: 20)
            button.image = image
        } else {
            let image = NSImage(systemSymbolName: "infinity", accessibilityDescription: "Always Online")
            image?.isTemplate = true
            image?.size = NSSize(width: 20, height: 20)
            button.image = image
        }
        button.imageScaling = .scaleProportionallyUpOrDown
        button.imagePosition = .imageOnly
        button.toolTip = "Always Online"
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.action = #selector(statusItemClicked(_:))

        let dot = StatusDotView(frame: NSRect(x: button.bounds.maxX - 5, y: 2, width: 4, height: 4))
        dot.isHidden = !engine.running
        statusDot = dot
        button.addSubview(dot, positioned: .above, relativeTo: nil)

        let panel = NSPopover()
        panel.behavior = .transient
        panel.delegate = self
        let hostingController = NSHostingController(rootView: ContentView(engine: engine))
        hostingController.sizingOptions = [.preferredContentSize]
        panel.contentSize = NSSize(width: 340, height: 450)
        panel.contentViewController = hostingController
        popover = panel

        engine.$running.sink { [weak dot] running in
            Task { @MainActor in dot?.running = running }
        }.store(in: &subscriptions)
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeOutsideClickMonitor()
        engine.endPanelRefresh()
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
        engine.endPanelRefresh()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover?.performClose(nil)
            removeOutsideClickMonitor()
            engine.endPanelRefresh()
            showQuickMenu(from: sender)
        } else if let popover {
            if popover.isShown {
                popover.performClose(nil)
                removeOutsideClickMonitor()
                engine.endPanelRefresh()
            } else {
                NSApp.activate(ignoringOtherApps: true)
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
                engine.beginPanelRefresh()
                installOutsideClickMonitor()
            }
        }
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in self?.dismissPopover(ifOutside: location) }
        }
    }

    private func dismissPopover(ifOutside location: NSPoint) {
        guard let popover, popover.isShown else {
            removeOutsideClickMonitor()
            return
        }
        if let panelFrame = popover.contentViewController?.view.window?.frame, !panelFrame.contains(location) {
            popover.performClose(nil)
            removeOutsideClickMonitor()
            engine.endPanelRefresh()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func showQuickMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let action = NSMenuItem(title: engine.running ? "停止运行" : "开始运行", action: #selector(toggleRunning), keyEquivalent: "")
        action.target = self
        action.image = NSImage(systemSymbolName: engine.running ? "stop.fill" : "play.fill", accessibilityDescription: nil)
        menu.addItem(action)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Always Online", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }

    @objc private func toggleRunning() {
        if engine.running { engine.stop() } else { engine.start() }
    }

    @objc private func quit() {
        engine.stop()
        NSApplication.shared.terminate(nil)
    }
}

@MainActor private final class StatusDotView: NSView {
    var running = false { didSet { isHidden = !running; needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

@main struct AlwaysOnlineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
