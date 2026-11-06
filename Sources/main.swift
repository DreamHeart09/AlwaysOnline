import Foundation
import AppKit
import ApplicationServices
import IOKit
import IOKit.pwr_mgt

struct Options {
    var mode = "observe"
    var interval = 300.0
    var duration = 0.0
    var sample = 5.0
    init() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") { print("Usage: always-online [--mode observe|flags|mouse|power|user-activity] [--interval seconds] [--sample seconds] [--duration seconds]\nDefault is observation only. Ctrl-C stops. Synthetic modes need Accessibility permission."); exit(0) }
        var i = 0
        while i < args.count {
            guard i + 1 < args.count else { fputs("Missing value for \(args[i])\n", stderr); exit(2) }
            let key = args[i], value = args[i+1]
            switch key {
            case "--mode": mode = value
            case "--interval": interval = Double(value) ?? -1
            case "--sample": sample = Double(value) ?? -1
            case "--duration": duration = Double(value) ?? -1
            default: fputs("Unknown option: \(key)\n", stderr); exit(2)
            }
            i += 2
        }
        guard ["observe", "flags", "mouse", "power", "user-activity"].contains(mode), interval >= 2, sample >= 1, duration >= 0, interval.isFinite, sample.isFinite, duration.isFinite else { fputs("Invalid options; use --help\n", stderr); exit(2) }
    }
}
func log(_ s: String) { print("\(ISO8601DateFormatter().string(from: Date())) \(s)"); fflush(stdout) }
func hidIdle() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard let n = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else { return nil }
    return n.doubleValue / 1_000_000_000
}
func seconds(_ state: CGEventSourceStateID) -> String { String(format: "%.1f", CGEventSource.secondsSinceLastEventType(state, eventType: .null)) }
func snapshot() -> String {
    let hid = hidIdle().map { String(format: "%.1f", $0) } ?? "unavailable"
    return "HID=\(hid)s CG.hid=not-sampled CG.combined=\(seconds(.combinedSessionState))s CG.private=not-sampled"
}
func wecom() -> String {
    let apps = NSWorkspace.shared.runningApplications.filter { app in
        let name = (app.localizedName ?? "").lowercased(), id = (app.bundleIdentifier ?? "").lowercased()
        return name.contains("企业微信") || name.contains("wecom") || id.contains("wxwork") || id.contains("wework")
    }
    return apps.isEmpty ? "not detected (heuristic)" : apps.map { "\($0.localizedName ?? "?") [\($0.bundleIdentifier ?? "?")] pid=\($0.processIdentifier)" }.joined(separator: ", ")
}
// This session dictionary is an empirical guard, not a documented lock guarantee.
func sessionSafe() -> Bool {
    guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any], let console = dict[kCGSessionOnConsoleKey as String] as? Bool, console else { return false }
    return !(dict["CGSSessionScreenIsLocked"] as? Bool ?? false)
}
func nudge(_ mode: String) {
    guard sessionSafe() else { log("SKIP session locked, off-console, or unknown"); return }
    guard AXIsProcessTrusted() else { log("SKIP Accessibility not granted; no event posted"); return }
    guard !CGEventSource.buttonState(.combinedSessionState, button: .left), !CGEventSource.buttonState(.combinedSessionState, button: .right), !CGEventSource.buttonState(.combinedSessionState, button: .center) else { log("SKIP mouse button held"); return }
    let flags = CGEventSource.flagsState(.combinedSessionState)
    guard flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty else { log("SKIP modifier held"); return }
    log("BEFORE \(snapshot())")
    if mode == "flags" {
        guard let event = CGEvent(source: nil) else { log("ERROR creating event"); return }
        event.type = .flagsChanged; event.flags = flags
        event.post(tap: .cghidEventTap)
        log("POST flagsChanged called (API has no delivery result; effectiveness unverified)")
    } else {
        guard let original = CGEvent(source: nil)?.location else { log("ERROR reading cursor"); return }
        let displays = (0..<CGDisplayCount(16)).map { _ in CGDirectDisplayID(0) }
        var ids = displays, count: CGDisplayCount = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { log("ERROR display list"); return }
        let bounds = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        guard let rect = bounds.first(where: { $0.contains(original) }) else { log("SKIP cursor outside active display"); return }
        let target = CGPoint(x: original.x + (original.x + 1 < rect.maxX ? 1 : -1), y: original.y)
        guard rect.contains(target), let first = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left), let second = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: original, mouseButton: .left) else { log("ERROR creating mouse events"); return }
        first.post(tap: .cghidEventTap); second.post(tap: .cghidEventTap)
        log("POST mouse round trip called (delivery and side effects unverified)")
    }
    usleep(200_000)
    log("AFTER \(snapshot())")
}
let options = Options()
log("mode=\(options.mode) interval=\(options.interval)s sample=\(options.sample)s duration=\(options.duration)s")
log("Accessibility=\(AXIsProcessTrusted() ? "granted" : "not granted") WeCom=\(wecom())")
log("Idle counters are system observations, not proven physical-user-only timers. WeCom status is NOT measured.")
var assertion: IOPMAssertionID = 0
if options.mode == "power" {
    let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Always Online PoC" as CFString, &assertion)
    log("power assertion result=\(result) id=\(assertion)")
    if result != kIOReturnSuccess { exit(1) }
}
defer { if assertion != 0 { IOPMAssertionRelease(assertion) } }
let start = Date(), deadline = start.addingTimeInterval(options.duration), first = start.addingTimeInterval(options.interval)
var nextEvent = first, nextSample = start
while options.duration == 0 || Date() < deadline {
    let now = Date()
    if now >= nextSample { log("SAMPLE \(snapshot()) WeCom=\(wecom())"); nextSample = now.addingTimeInterval(options.sample) }
    if now >= nextEvent {
        if options.mode == "flags" || options.mode == "mouse" { nudge(options.mode) }
        if options.mode == "user-activity" {
            if sessionSafe() {
                let result = IOPMAssertionDeclareUserActivity("Always Online PoC" as CFString, kIOPMUserActiveLocal, &assertion)
                log("DECLARE_USER_ACTIVITY result=\(result) id=\(assertion) \(snapshot())")
            } else { log("SKIP session locked, off-console, or unknown") }
        }
        nextEvent = now.addingTimeInterval(options.interval)
    }
    Thread.sleep(forTimeInterval: 0.2)
}
log("Stopped")
