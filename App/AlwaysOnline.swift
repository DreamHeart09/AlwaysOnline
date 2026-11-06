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

private let runningIndicatorColor = NSColor(
    name: NSColor.Name("AlwaysOnlineRunningIndicator"),
    dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.35, green: 0.76, blue: 0.50, alpha: 1)
            : NSColor(srgbRed: 0.16, green: 0.52, blue: 0.32, alpha: 1)
    }
)

private let segmentSelectionColor = NSColor(
    name: NSColor.Name("AlwaysOnlineSegmentSelection"),
    dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.31, green: 0.32, blue: 0.36, alpha: 1)
            : NSColor(srgbRed: 0.99, green: 0.99, blue: 1.0, alpha: 1)
    }
)

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
        last = "\(Date().formatted(date: .omitted, time: .standard)) 已调用事件投递"
    }
}

private enum PopoverTokens {
    static let width: CGFloat = 340
    static let outerInset: CGFloat = 17
    static let compactSpacing: CGFloat = 5
    static let tightSpacing: CGFloat = 8
    static let inlineSpacing: CGFloat = 10
    static let groupSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 16
    static let cardInset: CGFloat = 14
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 9
    static let statusIconSize: CGFloat = 26
    static let eventIconSize: CGFloat = 28
    static let segmentHeight: CGFloat = 30
    static let primaryActionHeight: CGFloat = 38
    static let menuHitWidth: CGFloat = 36
    static let menuHitHeight: CGFloat = 34
    static let accent = Color(nsColor: .controlAccentColor)
    static let separator = Color(nsColor: .separatorColor).opacity(0.62)
    static let outline = Color.primary.opacity(0.085)
    static let subtleSurface = Color.primary.opacity(0.045)
    static let controlTrack = Color.primary.opacity(0.075)
    static let selectedControlSurface = Color(nsColor: segmentSelectionColor)
    static let title = Font.system(size: 15, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 12, weight: .semibold, design: .default)
    static let body = Font.system(size: 12, weight: .medium, design: .default)
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let statusLabel = Font.system(size: 11, weight: .medium, design: .default)
    static let microLabel = Font.system(size: 10, weight: .semibold, design: .default)
}

struct ContentView: View {
    @ObservedObject var engine: Engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var interaction = PopoverInteractionState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 0) {
                statusRow(icon: "message", title: "企业微信", value: engine.wecom == "已检测到" ? "已检测" : engine.wecom)
                Divider().padding(.leading, 39)
                statusRow(
                    icon: "hand.raised",
                    title: "辅助功能",
                    value: engine.trusted ? "已授权" : "",
                    needsAttention: !engine.trusted,
                    actionTitle: engine.trusted ? nil : "开启权限",
                    action: engine.trusted ? nil : { engine.requestPermission() }
                )
            }
            .padding(.top, PopoverTokens.sectionSpacing)

            settingsCard
                .padding(.top, PopoverTokens.sectionSpacing)

            recentEvent
                .padding(.top, PopoverTokens.groupSpacing)

            Divider()
                .overlay(PopoverTokens.separator)
                .padding(.top, PopoverTokens.sectionSpacing)
                .padding(.bottom, PopoverTokens.groupSpacing)

            actionArea
        }
        .padding(.horizontal, PopoverTokens.outerInset)
        .padding(.vertical, 16)
        .frame(width: PopoverTokens.width)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: engine.trusted)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: engine.running)
        .onAppear { engine.refresh() }
    }

    private var header: some View {
        HStack(spacing: PopoverTokens.groupSpacing) {
            if let image = menuBarBrandImage {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(PopoverTokens.accent)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "infinity")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(PopoverTokens.accent)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: PopoverTokens.compactSpacing - 1) {
                Text("Always Online")
                    .font(PopoverTokens.title)
                    .tracking(-0.22)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(engine.running ? "每 \(intervalLabel) 尝试维持活动状态" : stoppedDetail)
                    .font(PopoverTokens.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            HStack(spacing: PopoverTokens.compactSpacing) {
                Image(systemName: engine.running ? "checkmark.circle.fill" : "pause.circle")
                    .font(.system(size: 11, weight: .medium))
                Text(engine.running ? "运行中" : "已停止")
                    .font(PopoverTokens.statusLabel.weight(.semibold))
                    .fixedSize()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, PopoverTokens.tightSpacing)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(PopoverTokens.outline, lineWidth: 0.7))
            .accessibilityElement(children: .combine)
        }
        .frame(height: 44)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: PopoverTokens.groupSpacing) {
            HStack(spacing: PopoverTokens.tightSpacing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PopoverTokens.accent)
                    .frame(width: 18, height: 18)
                Text("运行设置")
                    .font(PopoverTokens.sectionTitle)
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 10) {
                settingRow(title: "活动模式", values: ["无位移", "鼠标微移"], selection: Binding(
                    get: { engine.mode == "无位移" ? "无位移" : "鼠标微移" },
                    set: { engine.mode = $0 }
                ), disabled: engine.running)

                settingRow(title: "发送间隔", values: ["1 分钟", "5 分钟", "10 分钟"], selection: Binding(
                    get: { engine.interval == 60 ? "1 分钟" : (engine.interval == 300 ? "5 分钟" : "10 分钟") },
                    set: { engine.interval = $0 == "1 分钟" ? 60 : ($0 == "5 分钟" ? 300 : 600) }
                ), disabled: engine.running)
            }
        }
        .padding(PopoverTokens.cardInset)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PopoverTokens.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PopoverTokens.cardRadius, style: .continuous)
                .strokeBorder(PopoverTokens.outline, lineWidth: 0.8)
        }
    }

    private var recentEvent: some View {
        HStack(alignment: .center, spacing: PopoverTokens.inlineSpacing) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
            .frame(width: PopoverTokens.eventIconSize, height: PopoverTokens.eventIconSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("最近事件")
                    .font(PopoverTokens.sectionTitle)
                    .foregroundStyle(.primary)
                Text(engine.last == "尚未发送" ? "尚未发送" : engine.last)
                    .font(PopoverTokens.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private var actionArea: some View {
        HStack(spacing: PopoverTokens.tightSpacing + 1) {
            Button { engine.running ? engine.stop() : engine.start() } label: {
                Label(engine.running ? "停止" : "开始运行", systemImage: engine.running ? "stop.fill" : "play.fill")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .frame(height: PopoverTokens.primaryActionHeight)
            }
            .buttonStyle(PremiumActionButtonStyle(prominent: !engine.running, isHovered: interaction.actionHovered))
            .onHover { interaction.actionHovered = $0 }
            .help(engine.running ? "停止运行" : "开始运行")

            Menu {
                Button("退出 Always Online", systemImage: "power") {
                    engine.stop()
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: PopoverTokens.menuHitWidth, height: PopoverTokens.menuHitHeight)
                    .background(
                        PopoverTokens.subtleSurface.opacity(interaction.menuHovered ? 1.45 : 1),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(PopoverTokens.outline, lineWidth: 0.7)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .onHover { interaction.menuHovered = $0 }
            .help("更多操作")
            .accessibilityLabel("更多操作")
        }
    }

    private var intervalLabel: String {
        engine.interval == 60 ? "1 分钟" : (engine.interval == 300 ? "5 分钟" : "10 分钟")
    }

    private var stoppedDetail: String {
        if !engine.trusted { return "需要辅助功能权限" }
        if engine.status == "已停止" { return "按需开始运行" }
        return engine.status
    }

    private func settingRow(title: String, values: [String], selection: Binding<String>, disabled: Bool) -> some View {
        HStack(spacing: PopoverTokens.inlineSpacing) {
            Text(title)
                .font(PopoverTokens.body)
                .foregroundStyle(.primary)
                .frame(width: 58, alignment: .leading)

            PremiumSegmentedControl(values: values, selection: selection)
                .disabled(disabled)
                .opacity(disabled ? 0.68 : 1)
        }
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
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
            .frame(width: PopoverTokens.statusIconSize, height: PopoverTokens.statusIconSize)
            .accessibilityHidden(true)

            Text(title)
                .font(PopoverTokens.body)
                .foregroundStyle(.primary)
            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, systemImage: "arrow.up.right.square", action: action)
                    .font(PopoverTokens.statusLabel)
                    .buttonStyle(.link)
            } else {
                HStack(spacing: 5) {
                    if !needsAttention {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text(value)
                        .font(PopoverTokens.statusLabel)
                }
                .foregroundStyle(needsAttention ? Color.orange : Color.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 6)
    }
}

private struct PremiumSegmentedControl: View {
    let values: [String]
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @StateObject private var interaction = SegmentInteractionState()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                segmentButton(value)
            }
        }
        .padding(3)
        .background(PopoverTokens.controlTrack, in: RoundedRectangle(cornerRadius: PopoverTokens.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PopoverTokens.controlRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.045), lineWidth: 0.65)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: interaction.hoveredValue)
        .accessibilityElement(children: .contain)
    }

    private func segmentButton(_ value: String) -> some View {
        let isSelected = selection == value

        return Button {
            guard !isSelected else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.17)) {
                selection = value
            }
        } label: {
            Text(value)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .default))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: PopoverTokens.segmentHeight)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(PopoverTokens.selectedControlSurface)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(PopoverTokens.outline, lineWidth: 0.75)
                            }
                            .shadow(color: Color.black.opacity(0.085), radius: 1.5, y: 1)
                            .matchedGeometryEffect(id: "selected-segment", in: selectionNamespace)
                    } else if interaction.hoveredValue == value {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            interaction.hoveredValue = hovering ? value : (interaction.hoveredValue == value ? nil : interaction.hoveredValue)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(value)
        .accessibilityHint(isSelected ? "当前选择" : "选择此选项")
    }
}

private struct PremiumActionButtonStyle: ButtonStyle {
    let prominent: Bool
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = prominent
            ? PopoverTokens.accent.opacity(pressed ? 0.86 : (isHovered ? 1 : 0.94))
            : Color(nsColor: .controlBackgroundColor)

        return configuration.label
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(prominent ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(prominent ? Color.white.opacity(0.18) : PopoverTokens.outline, lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(prominent ? 0.12 : 0.045), radius: pressed ? 1 : 2.5, y: pressed ? 0 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.988 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}

@MainActor private final class PopoverInteractionState: ObservableObject {
    @Published var actionHovered = false
    @Published var menuHovered = false
}

@MainActor private final class SegmentInteractionState: ObservableObject {
    @Published var hoveredValue: String?
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let engine = Engine()
    private var statusItem: NSStatusItem?
    private var statusDot: StatusDotView?
    private var popover: NSPopover?
    private var quickMenuPopover: NSPopover?
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

        let dotSize: CGFloat = 6
        let iconSize: CGFloat = 20
        let iconBounds = NSRect(
            x: button.bounds.midX - iconSize / 2,
            y: button.bounds.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        let dotInset: CGFloat = 2
        let dotY = button.isFlipped
            ? iconBounds.maxY - dotSize + dotInset - 2
            : iconBounds.minY - dotInset + 2
        let dot = StatusDotView(frame: NSRect(
            x: iconBounds.maxX - dotSize + dotInset,
            y: dotY,
            width: dotSize,
            height: dotSize
        ))
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
        if let closedPopover = notification.object as? NSPopover, closedPopover === quickMenuPopover {
            quickMenuPopover = nil
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover?.performClose(nil)
            removeOutsideClickMonitor()
            engine.endPanelRefresh()
            quickMenuPopover?.performClose(nil)
            showQuickMenu(from: sender)
        } else {
            quickMenuPopover?.performClose(nil)
            guard let popover else { return }
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
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSPopover()
        panel.behavior = .transient
        panel.animates = true
        panel.delegate = self
        panel.contentSize = NSSize(width: 220, height: 86)
        panel.contentViewController = NSHostingController(rootView: QuickMenuView(
            isRunning: engine.running,
            onToggle: { [weak self] in self?.performQuickMenuAction { self?.toggleRunning() } },
            onQuit: { [weak self] in self?.performQuickMenuAction { self?.quit() } }
        ))

        quickMenuPopover = panel
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        panel.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    private func performQuickMenuAction(_ action: () -> Void) {
        quickMenuPopover?.performClose(nil)
        action()
    }

    @objc private func toggleRunning() {
        if engine.running { engine.stop() } else { engine.start() }
    }

    @objc private func quit() {
        engine.stop()
        NSApplication.shared.terminate(nil)
    }
}

private struct QuickMenuView: View {
    let isRunning: Bool
    let onToggle: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            QuickMenuRow(
                title: isRunning ? "停止运行" : "开始运行",
                symbol: isRunning ? "stop.fill" : "play.fill",
                action: onToggle
            )

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 1)

            QuickMenuRow(title: "退出 Always Online", symbol: "power", action: onQuit)
        }
        .padding(6)
        .frame(width: 220)
    }
}

private struct QuickMenuRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @StateObject private var interaction = QuickMenuRowInteraction()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 31)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                interaction.isHovered ? Color.primary.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { interaction.isHovered = $0 }
    }
}

@MainActor private final class QuickMenuRowInteraction: ObservableObject {
    @Published var isHovered = false
}

@MainActor private final class StatusDotView: NSView {
    var running = false { didSet { isHidden = !running; needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        runningIndicatorColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

@main struct AlwaysOnlineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
