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
        "incognito", "инкогнито", "режим инкогнито", "inprivate", "private browsing", "private window", "private",
        "частный доступ", "приватный режим", "приватное окно", "приватный просмотр", "приватный",
    ]

    private static let lock = NSLock()
    private static var verdicts: [CFHashCode: Bool] = [:]
    private static var scanning: Set<CFHashCode> = []
    private static let queue = DispatchQueue(label: "ActivityTracker.private-window", qos: .utility)

    static func verdict(for pid: pid_t) -> Verdict {
        guard AXIsProcessTrusted() else { return .normal }   // nothing to look at without the permission
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return .normal }
        let window = value as! AXUIElement
        let key = CFHash(window)

        lock.lock()
        defer { lock.unlock() }
        if let known = verdicts[key] { return known ? .privateWindow : .normal }
        if !scanning.contains(key) {
            scanning.insert(key)
            queue.async {
                let isPrivate = scan(window)
                lock.lock()
                if verdicts.count > 200 { verdicts.removeAll() }
                verdicts[key] = isPrivate
                scanning.remove(key)
                lock.unlock()
            }
        }
        return .unknown
    }

    private static func scan(_ window: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(window, 0.5)
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var visited = 0
        while !queue.isEmpty && visited < 250 {
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

    private static var scripts: [String: NSAppleScript] = [:]
    /// Last AppleScript error per browser bundle ID; -1743 means the user denied Automation access.
    private(set) static var lastErrors: [String: Int] = [:]

    static let notPermittedError = -1743

    static func isBrowser(_ bundleID: String) -> Bool {
        safariFamily.contains(bundleID) || chromiumFamily.contains(bundleID) || firefoxFamily.contains(bundleID)
    }

    /// Firefox has no AppleScript, but its private windows say so in the title.
    static func isPrivateWindowTitle(_ title: String, bundleID: String) -> Bool {
        guard firefoxFamily.contains(bundleID) else { return false }
        return ["Private Browsing", "Приватный просмотр", "Приватное окно"].contains { title.contains($0) }
    }

    /// Must be called on the main thread (NSAppleScript is not thread-safe).
    static func currentURL(bundleID: String) -> String {
        guard let script = script(for: bundleID) else { return "" }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            lastErrors[bundleID] = (error[NSAppleScript.errorNumber] as? Int) ?? -1
            return ""
        }
        lastErrors[bundleID] = nil
        return result.stringValue ?? ""
    }

    private static func script(for bundleID: String) -> NSAppleScript? {
        if let cached = scripts[bundleID] { return cached }
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
        // A short timeout: a hung browser must not freeze the menu bar app.
        let source = """
            with timeout of 2 seconds
                tell application id "\(bundleID)"
            \(body)
                end tell
            end timeout
            """
        let script = NSAppleScript(source: source)
        scripts[bundleID] = script
        return script
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
