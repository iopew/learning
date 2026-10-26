import AppKit
import ApplicationServices
import IOKit.pwr_mgt

/// Title of the focused window of an app. Needs the Accessibility permission
/// (System Settings → Privacy & Security → Accessibility); without it titles are simply empty.
enum WindowTitle {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt (only if not trusted yet).
    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func focusedWindowTitle(of pid: pid_t) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return "" }

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String
        else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension WindowTitle {
    /// A readable dump of the focused window's accessibility tree (roles, titles, descriptions), used to find
    /// markers such as Safari's private-window indicator. Depth- and size-limited.
    static func describeFocusedWindow(of app: NSRunningApplication) -> String {
        guard AXIsProcessTrusted() else { return "Нет доступа «Универсальный доступ»." }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return "\(app.localizedName ?? "?"): нет активного окна." }

        var lines = ["app: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"))"]
        func string(_ element: AXUIElement, _ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            if let text = value as? String, !text.isEmpty { return text }
            if let flag = value as? Bool { return flag ? "true" : "false" }
            return nil
        }
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= 6, lines.count < 400 else { return }
            let fields = ["AXRole", "AXSubrole", "AXIdentifier", "AXTitle", "AXDescription", "AXValue", "AXHelp",
                          "AXRoleDescription"]
                .compactMap { key in string(element, key).map { "\(key.dropFirst(2))=\($0.prefix(120))" } }
            lines.append(String(repeating: "  ", count: depth) + fields.joined(separator: " | "))
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                  let list = children as? [AXUIElement] else { return }
            for child in list.prefix(40) { walk(child, depth: depth + 1) }
        }
        walk(window as! AXUIElement, depth: 0)
        return lines.joined(separator: "\n")
    }
}

/// Recognises private / incognito windows by the browser's own UI: Chromium-based browsers show an "Incognito"
/// badge in the toolbar (Яндекс: «Инкогнито», Edge: "InPrivate"). Only the window chrome is searched, never page
/// content or tab titles. Each window is scanned once, in the background; until its verdict is known the window is
/// treated as private (a few seconds are skipped rather than a private page recorded).
enum PrivateWindowDetector {
    enum Verdict {
        case normal, privateWindow, unknown
    }

    /// Lower-case badge texts. Matched as the whole label or its first/last word, so a page or bookmark that merely
    /// mentions "incognito" in a longer text doesn't count.
    static let markers = [
        "incognito", "инкогнито", "режим инкогнито", "inprivate", "private browsing", "private window",
        "частный доступ", "приватный режим", "приватное окно", "приватный просмотр",
    ]

    private static let lock = NSLock()
    private static var verdicts: [CFHashCode: (isPrivate: Bool, checked: Date)] = [:]
    private static var scanning: Set<CFHashCode> = []
    private static let queue = DispatchQueue(label: "ActivityTracker.private-window", qos: .utility)

    static func verdict(for pid: pid_t, bundleID: String) -> Verdict {
        guard AXIsProcessTrusted() else { return .normal }   // nothing to look at without the permission
        let app = AXUIElementCreateApplication(pid)
        // Runs on the main thread in the tick: a hung app may cost at most a fraction of a second.
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return .normal }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.2)

        // Instant signals. Chromium browsers add " (Incognito)" / « (Инкогнито)» to the window's accessible title;
        // Arc names incognito windows "bigIncognitoBrowserWindow-…".
        if let title = text(window, kAXTitleAttribute), titleSaysPrivate(title) { return .privateWindow }
        if let identifier = text(window, "AXIdentifier"), identifier.lowercased().contains("incognito") {
            return .privateWindow
        }

        let key = CFHash(window)

        lock.lock()
        defer { lock.unlock() }
        let known = verdicts[key]
        let fresh = known.map { Date().timeIntervalSince($0.checked) < 600 } ?? false
        if !fresh && !scanning.contains(key) {
            scanning.insert(key)
            queue.async {
                // Safari has no badge: its Window menu says "Move Tab to New Private Window" instead.
                let isPrivate = BrowserURL.isSafari(bundleID) ? safariWindowMenuSaysPrivate(pid: pid) : scan(window)
                lock.lock()
                if verdicts.count > 200 { verdicts.removeAll() }
                verdicts[key] = (isPrivate, Date())
                scanning.remove(key)
                lock.unlock()
            }
        }
        // While a re-check runs, the previous verdict stands; only a never-seen window is "unknown".
        if let known { return known.isPrivate ? .privateWindow : .normal }
        return .unknown
    }

    private static func scan(_ window: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(window, 0.5)
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var visited = 0
        // The window counts as unknown (not recorded) while it is scanned: never longer than 3 seconds.
        let deadline = Date().addingTimeInterval(3)
        while !queue.isEmpty && visited < 250 && Date() < deadline {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = text(element, kAXRoleAttribute)
            if role == "AXWebArea" || role == "AXTabGroup" { continue }   // page content, tab titles
            for attribute in [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute] {
                if let label = text(element, attribute), matches(label) { return true }
            }
            guard depth < 8 else { continue }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let list = children as? [AXUIElement] {
                queue.append(contentsOf: list.prefix(40).map { ($0, depth + 1) })
            }
        }
        return false
    }

    static func titleSaysPrivate(_ title: String) -> Bool {
        let text = title.lowercased()
        return ["(incognito)", "(инкогнито)", "(inkognito)", "(private)", "(приватное)", "(приватный)", "inprivate"]
            .contains { text.contains($0) }
    }

    /// Safari's Window menu has "Move Tab to New Private Window" (ru: «Переместить вкладку в новое частное окно»)
    /// while a private window is in front, "… New Window" otherwise. Read through Accessibility without opening it.
    static func safariWindowMenuSaysPrivate(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success, let bar,
              CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return false }
        for item in children(bar as! AXUIElement) {
            guard let title = text(item, kAXTitleAttribute)?.lowercased(), title == "window" || title == "окно" else {
                continue
            }
            for menu in children(item) {
                for entry in children(menu) {
                    guard let label = text(entry, kAXTitleAttribute)?.lowercased() else { continue }
                    let movesTab = label.contains("move tab to new") || label.contains("переместить вкладку")
                    if movesTab && (label.contains("private") || label.contains("частн")) { return true }
                }
            }
        }
        return false
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func matches(_ label: String) -> Bool {
        let text = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 40 else { return false }
        return markers.contains { marker in
            text == marker || text.hasPrefix(marker + " ") || text.hasPrefix(marker + ",") || text.hasPrefix(marker + ":")
                || text.hasPrefix(marker + " (") || text.hasSuffix(" " + marker) || text.hasSuffix("(" + marker + ")")
        }
    }

    private static func text(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

/// URL of the active tab, asked from the browser over AppleScript. macOS asks the user once per browser
/// (Privacy & Security → Automation). Firefox has no AppleScript support, so only its window title is recorded.
enum BrowserURL {
    private static let safariFamily: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]
    private static let chromiumFamily: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "ru.yandex.desktop.yandex-browser",
    ]
    private static let firefoxFamily: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
    ]

    /// Returned instead of a URL when the front window is private (incognito).
    static let privateMarker = "__private__"

    /// Last AppleScript error per browser bundle ID; -1743 means the user denied Automation access.
    static var lastErrors: [String: Int] {
        errorLock.lock()
        defer { errorLock.unlock() }
        return errors
    }
    private static var errors: [String: Int] = [:]
    private static let errorLock = NSLock()

    static let notPermittedError = -1743

    static func isSafari(_ bundleID: String) -> Bool {
        safariFamily.contains(bundleID)
    }

    static func isBrowser(_ bundleID: String) -> Bool {
        safariFamily.contains(bundleID) || chromiumFamily.contains(bundleID) || firefoxFamily.contains(bundleID)
    }

    /// Firefox has no AppleScript, but its private windows say so in the title.
    static func isPrivateWindowTitle(_ title: String, bundleID: String) -> Bool {
        guard firefoxFamily.contains(bundleID) else { return false }
        return ["Private Browsing", "Приватный просмотр", "Приватное окно"].contains { title.contains($0) }
    }

    /// Asks the browser for the front tab's URL by running `osascript` — a separate process, so neither a slow
    /// browser nor macOS's "allow ActivityTracker to control …?" prompt can ever block the app. Killed after
    /// `timeout`. Blocking: call it from a background queue only.
    static func fetchURL(bundleID: String, timeout: TimeInterval = 4) -> String? {
        guard let source = scriptSource(for: bundleID) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            setError(-1712, for: bundleID)   // timed out (e.g. waiting for the user to answer the permission prompt)
            return nil
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            // osascript reports "… (-1743)" when Automation access was denied.
            let code = message.range(of: #"\((-?\d+)\)"#, options: .regularExpression)
                .flatMap { Int(message[$0].dropFirst().dropLast()) } ?? -1
            setError(code, for: bundleID)
            return nil
        }
        setError(nil, for: bundleID)
        return text
    }

    private static func setError(_ code: Int?, for bundleID: String) {
        errorLock.lock()
        errors[bundleID] = code
        errorLock.unlock()
    }

    private static func scriptSource(for bundleID: String) -> String? {
        let body: String
        if safariFamily.contains(bundleID) {
            body = "return URL of front document"
        } else if chromiumFamily.contains(bundleID) {
            // Chrome-like browsers say `mode` = "incognito", Arc says `incognito` = true. Each check sits in its
            // own `try`: a browser that doesn't know the property just skips it.
            body = """
                set w to front window
                try
                    if (mode of w as text) is "incognito" then return "\(privateMarker)"
                end try
                try
                    if (incognito of w) is true then return "\(privateMarker)"
                end try
                return URL of active tab of w
                """
        } else {
            return nil
        }
        return """
            with timeout of 2 seconds
                tell application id "\(bundleID)"
            \(body)
                end tell
            end timeout
            """
    }
}

/// Keeps the browser's front-tab URL per window, fetched in the background (see `BrowserURL.fetchURL`).
/// The tracker's tick only reads this cache, so it never waits for a browser.
final class BrowserURLCache {
    enum Lookup: Equatable {
        case url(String)
        /// A fetch for this window is under way: skip this tick rather than record the page without its site.
        case waiting
        /// No URL to be had (Firefox, no permission, browser not answering): record without a site.
        case unavailable
    }

    static let shared = BrowserURLCache()

    private struct Key: Hashable {
        var pid: pid_t
        var title: String
    }

    private struct Entry {
        var url: String?
        var fetchedAt: Date
    }

    private let queue = DispatchQueue(label: "ActivityTracker.browser-url", qos: .utility)
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Date] = [:]

    /// `title`: the focused window's title, so a new page (new title) triggers a new fetch right away.
    func lookup(bundleID: String, pid: pid_t, title: String) -> Lookup {
        let key = Key(pid: pid, title: title)
        let now = Date()
        lock.lock()
        defer { lock.unlock() }

        let entry = entries[key]
        // Without a window title (no Accessibility permission) a new page can't be told apart: refresh more often.
        // (Each refresh starts an osascript process: not more often than every 20 s.)
        let maxAge: TimeInterval = title.isEmpty ? 20 : 15
        if (entry == nil || now.timeIntervalSince(entry!.fetchedAt) > maxAge) && inFlight[key] == nil {
            inFlight[key] = now
            queue.async { [self] in
                let url = BrowserURL.fetchURL(bundleID: bundleID)
                lock.lock()
                if entries.count > 300 { entries.removeAll() }
                entries[key] = Entry(url: url, fetchedAt: Date())
                inFlight[key] = nil
                lock.unlock()
            }
        }
        if let entry {
            return entry.url.map(Lookup.url) ?? .unavailable
        }
        // First time this window/page is seen: wait for the fetch, but never for long.
        if let started = inFlight[key], now.timeIntervalSince(started) < 6 { return .waiting }
        return .unavailable
    }
}

enum Idle {
    /// Seconds since the last keyboard / mouse / trackpad event in this login session.
    static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// True while some app keeps the display awake: video players, browsers playing video, calls.
    static func isDisplaySleepPrevented() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dictionary = status?.takeRetainedValue() as? [String: Any]
        else { return false }
        return ((dictionary["PreventUserIdleDisplaySleep"] as? Int) ?? 0) > 0
    }
}
