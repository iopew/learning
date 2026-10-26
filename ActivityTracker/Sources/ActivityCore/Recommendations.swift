import Foundation

/// Everything the rules look at. Built by the app from today's report, the usual day and today's system report.
public struct RecommendationInput {
    public var today: Report
    public var baseline: UsageBaseline
    public var system: SystemReport?
    public var now: Date
    /// Minute of the day `now` falls on (0…1439), used to find the current streak in `today.minutes`.
    public var minuteOfDay: Int

    public init(today: Report, baseline: UsageBaseline, system: SystemReport?, now: Date, minuteOfDay: Int) {
        self.today = today
        self.baseline = baseline
        self.system = system
        self.now = now
        self.minuteOfDay = minuteOfDay
    }
}

/// Local, rule-based tips. No network, no AI: simple thresholds over the user's own history.
public enum Recommendations {
    /// Sites that are mostly entertainment / feeds.
    public static let entertainmentDomains: Set<String> = [
        "youtube.com", "m.youtube.com", "instagram.com", "tiktok.com", "twitter.com", "x.com", "reddit.com",
        "netflix.com", "twitch.tv", "vk.com", "facebook.com", "kinopoisk.ru", "ok.ru", "rutube.ru", "9gag.com",
        "pinterest.com", "hd.kinopoisk.ru", "music.youtube.com",
    ]
    /// Apps where the owner writes code or learns.
    public static let codingApps: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.jetbrains.goland", "com.jetbrains.intellij",
        "com.jetbrains.pycharm", "com.apple.Terminal", "com.googlecode.iterm2", "dev.zed.Zed", "dev.warp.Warp-Stable",
        "com.todesktop.230313mzl4w4u92", "com.sublimetext.4", "md.obsidian", "com.exafunction.windsurf",
    ]

    /// Browsers: their time is judged per site instead.
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "ru.yandex.desktop.yandex-browser", "org.mozilla.firefox", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    /// Empty minutes that make a break. Recording stops only after the idle threshold (3 min by default), so a real
    /// 5-minute break leaves just ~2 empty minutes.
    static let breakGap = 2
    static let longStreak: TimeInterval = 90 * 60

    public static func make(_ input: RecommendationInput) -> [Recommendation] {
        var tips: [Recommendation] = []
        let today = input.today
        let baseline = input.baseline
        let hasHistory = baseline.activeDays >= 3

        // 1. Sites above the usual day (or simply a lot of entertainment when there's no history yet).
        var flaggedDomains: [String] = []
        for site in today.domains.prefix(10) {
            let usual = baseline.domainsPerDay[site.domain] ?? 0
            let isFun = entertainmentDomains.contains(site.domain)
            if hasHistory, usual >= 10 * 60, site.seconds >= 30 * 60, site.seconds >= usual * 1.3 {
                let more = Int(((site.seconds / usual) - 1) * 100)
                tips.append(Recommendation(
                    id: "site-above-usual-\(site.domain)", kind: isFun ? .warning : .info, symbol: "chart.line.uptrend.xyaxis",
                    title: L.tr("\(site.domain): \(Format.duration(site.seconds)) сегодня",
                                "\(site.domain): \(Format.duration(site.seconds)) today"),
                    detail: L.tr("Это на \(more)% больше обычного (\(Format.duration(usual)) в день)."
                                    + (isFun ? " Может, хватит на сегодня?" : ""),
                                 "That's \(more)% more than usual (\(Format.duration(usual)) a day)."
                                    + (isFun ? " Maybe enough for today?" : ""))))
                flaggedDomains.append(site.domain)
            } else if isFun, site.seconds >= 60 * 60, !hasHistory || usual < 10 * 60 {
                tips.append(Recommendation(
                    id: "site-a-lot-\(site.domain)", kind: .warning, symbol: "play.rectangle",
                    title: L.tr("\(site.domain): уже \(Format.duration(site.seconds)) сегодня",
                                "\(site.domain): already \(Format.duration(site.seconds)) today"),
                    detail: L.tr("Рекомендую сегодня меньше \(site.domain).", "Consider less \(site.domain) today.")))
                flaggedDomains.append(site.domain)
            }
            if flaggedDomains.count >= 2 { break }
        }

        // 2. Apps above the usual day (browsers are covered by sites, coding apps by the positive tip).
        if hasHistory {
            for app in today.apps.prefix(8) where !codingApps.contains(app.bundleID) && !browsers.contains(app.bundleID) {
                let usual = baseline.appsPerDay[app.bundleID] ?? 0
                guard usual >= 15 * 60, app.seconds >= 45 * 60, app.seconds >= usual * 1.5 else { continue }
                tips.append(Recommendation(
                    id: "app-above-usual-\(app.bundleID)", kind: .info, symbol: "app.badge",
                    title: L.tr("\(app.appName): \(Format.duration(app.seconds)) сегодня",
                                "\(app.appName): \(Format.duration(app.seconds)) today"),
                    detail: L.tr("Обычно \(Format.duration(usual)) в день.", "Usually \(Format.duration(usual)) a day.")))
                break
            }
        }

        // 3. No break for a long time.
        let streak = currentStreak(minutes: today.minutes, endingAt: input.minuteOfDay)
        if today.range == .day, streak >= longStreak {
            tips.append(Recommendation(
                id: "long-streak", kind: .warning, symbol: "figure.walk",
                title: L.tr("\(Format.duration(streak)) без перерыва", "\(Format.duration(streak)) without a break"),
                detail: L.tr("Встань, разомнись и дай глазам отдохнуть 5–10 минут.",
                             "Stand up, stretch and rest your eyes for 5–10 minutes.")))
        }

        // 4. Late night.
        let night = lateNight(minutes: today.minutes, firstHour: today.firstHour)
        if night >= 20 * 60 {
            tips.append(Recommendation(
                id: "late-night", kind: .info, symbol: "moon.stars",
                title: L.tr("Ночью за компьютером: \(Format.duration(night))",
                            "At the computer at night: \(Format.duration(night))"),
                detail: L.tr("Экран после полуночи сбивает сон. Попробуй заканчивать пораньше.",
                             "Screens after midnight disturb sleep. Try to wrap up earlier.")))
        }

        // 5. A very long day.
        let longDay = max(8 * 3600, hasHistory ? baseline.totalPerDay * 1.4 : 0)
        if today.total >= longDay {
            tips.append(Recommendation(
                id: "long-day", kind: .warning, symbol: "hourglass",
                title: L.tr("Сегодня уже \(Format.duration(today.total)) за компьютером",
                            "\(Format.duration(today.total)) at the computer today"),
                detail: hasHistory
                    ? L.tr("Обычно \(Format.duration(baseline.totalPerDay)). Сделай паузу.",
                           "Usually \(Format.duration(baseline.totalPerDay)). Take a break.")
                    : L.tr("Сделай паузу.", "Take a break.")))
        }

        // 6. Coding vs. entertainment.
        let coding = today.apps.filter { codingApps.contains($0.bundleID) }.reduce(0) { $0 + $1.seconds }
        let fun = today.domains.filter { entertainmentDomains.contains($0.domain) }.reduce(0) { $0 + $1.seconds }
        let usualCoding = baseline.appsPerDay.filter { codingApps.contains($0.key) }.reduce(0) { $0 + $1.value }
        if coding >= 30 * 60, !hasHistory || coding >= usualCoding * 1.2 {
            tips.append(Recommendation(
                id: "coding-good", kind: .positive, symbol: "chevron.left.forwardslash.chevron.right",
                title: L.tr("Код и учёба: \(Format.duration(coding)) сегодня",
                            "Coding and learning: \(Format.duration(coding)) today"),
                detail: hasHistory && usualCoding > 0
                    ? L.tr("Больше обычного (\(Format.duration(usualCoding))). Так держать!",
                           "More than usual (\(Format.duration(usualCoding))). Keep it up!")
                    : L.tr("Отличный темп. Так держать!", "Great pace. Keep it up!")))
        } else if fun >= 60 * 60, fun > coding {
            tips.append(Recommendation(
                id: "fun-over-code", kind: .info, symbol: "scalemass",
                title: L.tr("Развлечений больше, чем кода", "More entertainment than coding"),
                detail: L.tr("Развлечения \(Format.duration(fun)), код и учёба \(Format.duration(coding)).",
                             "Entertainment \(Format.duration(fun)), coding and learning \(Format.duration(coding)).")))
        }

        // 7. Battery and machine.
        if let system = input.system, system.hasData {
            tips.append(contentsOf: systemTips(system))
        }
        return tips
    }

    static func systemTips(_ system: SystemReport) -> [Recommendation] {
        var tips: [Recommendation] = []
        if let health = system.latest?.healthPercent, health < 80 {
            tips.append(Recommendation(
                id: "battery-health", kind: .warning, symbol: "battery.25",
                title: L.tr("Здоровье батареи \(Int(health))%", "Battery health \(Int(health))%"),
                detail: L.tr("Батарея заметно изношена. Если Mac быстро садится — пора думать о замене.",
                             "The battery is noticeably worn. If the Mac drains fast, consider a replacement.")))
        }
        if let top = system.energyOnBattery.first {
            let total = system.energyOnBattery.reduce(0) { $0 + $1.joules }
            if total > 0, top.joules / total >= 0.3, system.timeOnBattery >= 30 * 60 {
                let share = Int(top.joules / total * 100)
                tips.append(Recommendation(
                    id: "energy-top-\(top.bundleID)", kind: .info, symbol: "bolt.fill",
                    title: L.tr("\(top.appName) съел \(share)% энергии от батареи",
                                "\(top.appName) used \(share)% of battery energy"),
                    detail: L.tr("Закрывай его, когда не пользуешься, чтобы Mac дольше работал без зарядки.",
                                 "Quit it when you don't need it to make the battery last longer.")))
            }
        }
        if let drain = system.drainPerHour, drain >= 20 {
            tips.append(Recommendation(
                id: "fast-drain", kind: .warning, symbol: "battery.0",
                title: L.tr("Батарея садится быстро: \(Int(drain))% в час", "Fast drain: \(Int(drain))% per hour"),
                detail: L.tr("Посмотри вкладку «Батарея» — какие приложения тратят больше всего.",
                             "Check the Battery tab to see which apps use the most.")))
        }
        if system.timeFullOnAC >= 6 * 3600 {
            tips.append(Recommendation(
                id: "full-on-ac", kind: .info, symbol: "powerplug",
                title: L.tr("Батарея долго держится на 100%", "Battery kept at 100% for long"),
                detail: L.tr("\(Format.duration(system.timeFullOnAC)) на зарядке при 100%. Включи «Оптимизированную зарядку» в настройках батареи — так батарея проживёт дольше.",
                             "\(Format.duration(system.timeFullOnAC)) plugged in at 100%. Turn on Optimized Battery Charging to extend battery life.")))
        }
        if system.hotTime >= 15 * 60 {
            tips.append(Recommendation(
                id: "hot", kind: .warning, symbol: "thermometer.sun",
                title: L.tr("Mac перегревался \(Format.duration(system.hotTime))", "Mac ran hot for \(Format.duration(system.hotTime))"),
                detail: L.tr("Система снижала производительность. Проверь, что грузит процессор, и не закрывай вентиляцию.",
                             "macOS throttled performance. Check what loads the CPU and keep the vents clear.")))
        }
        if let latest = system.latest, latest.diskTotal > 0 {
            let freeShare = latest.diskFree / latest.diskTotal
            if freeShare < 0.1 || latest.diskFree < 15e9 {
                tips.append(Recommendation(
                    id: "disk", kind: .warning, symbol: "internaldrive",
                    title: L.tr("Мало места на диске: \(Format.bytes(latest.diskFree))",
                                "Low disk space: \(Format.bytes(latest.diskFree))"),
                    detail: L.tr("Когда места мало, macOS работает медленнее. Почисти загрузки и кэш.",
                                 "macOS slows down when the disk is nearly full. Clean up downloads and caches.")))
            }
        }
        if let swap = system.swapPeak, swap >= 4e9 {
            tips.append(Recommendation(
                id: "memory", kind: .info, symbol: "memorychip",
                title: L.tr("Не хватает памяти", "Running out of memory"),
                detail: L.tr("Mac использовал до \(Format.bytes(swap)) файла подкачки. Закрой лишние вкладки и приложения.",
                             "The Mac used up to \(Format.bytes(swap)) of swap. Close tabs and apps you don't need.")))
        }
        return tips
    }

    /// Active minutes counted back from `endingAt` until a break of `breakGap` empty minutes.
    static func currentStreak(minutes: [MinuteCell?], endingAt minute: Int) -> TimeInterval {
        guard !minutes.isEmpty else { return 0 }
        var index = min(minute, minutes.count - 1)
        // The user may be on a break right now: that time doesn't belong to any streak.
        var trailing = 0
        while index >= 0 && minutes[index] == nil {
            trailing += 1
            if trailing >= breakGap { return 0 }
            index -= 1
        }
        var active = 0
        var empty = 0
        while index >= 0 {
            if minutes[index] != nil {
                active += 1 + empty   // short gaps belong to the streak
                empty = 0
            } else {
                empty += 1
                if empty >= breakGap { break }
            }
            index -= 1
        }
        return TimeInterval(active * 60)
    }

    /// Seconds of activity between 00:00 and 05:00 by the clock. `minutes[0]` is `firstHour`:00 (the day may begin
    /// at 04:00, then the night is the tail of the day plus its first hour).
    static func lateNight(minutes: [MinuteCell?], firstHour: Int = 0) -> TimeInterval {
        var total: TimeInterval = 0
        for (index, cell) in minutes.enumerated() where (index / 60 + firstHour) % 24 < 5 {
            total += cell?.seconds ?? 0
        }
        return total
    }
}
