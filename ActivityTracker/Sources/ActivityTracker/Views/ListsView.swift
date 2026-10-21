import SwiftUI
import ActivityCore

/// Apps by time spent; click an app to see its most-used windows.
struct AppsList: View {
    let report: Report
    let colors: AppColors

    @State private var expanded: Set<String> = []

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if report.apps.isEmpty { EmptyNote() }
            ForEach(report.apps.prefix(50)) { app in
                VStack(alignment: .leading, spacing: 4) {
                    UsageRow(color: colors.color(app.bundleID), name: app.appName, seconds: app.seconds,
                             total: report.total,
                             expanded: app.topTitles.isEmpty ? nil : expanded.contains(app.bundleID))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if expanded.contains(app.bundleID) {
                                expanded.remove(app.bundleID)
                            } else {
                                expanded.insert(app.bundleID)
                            }
                        }
                    if expanded.contains(app.bundleID) {
                        ForEach(app.topTitles) { title in
                            HStack {
                                Text(title.title).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Format.duration(title.seconds)).monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }
}

struct SitesList: View {
    let report: Report

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if report.domains.isEmpty {
                EmptyNote(text: "Сайтов пока нет. Адреса берутся из Safari, Chrome, Arc, Brave, Edge, Яндекс Браузера и др.")
            }
            let browsing = report.domains.reduce(0) { $0 + $1.seconds }
            ForEach(report.domains) { site in
                UsageRow(color: .accentColor, name: site.domain, seconds: site.seconds, total: browsing)
            }
        }
    }
}

/// The day minute by minute: sessions of continuous use, newest first.
struct TimelineList: View {
    let sessions: [Session]
    let colors: AppColors

    @State private var showShort = false

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        let visible = Array((showShort ? sessions : sessions.filter { $0.duration >= 60 }).reversed())
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Показывать короткие (меньше минуты)", isOn: $showShort)
                .toggleStyle(.checkbox)
                .font(.caption)
            if visible.isEmpty { EmptyNote() }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(visible) { session in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(Self.time.string(from: session.start))–\(Self.time.string(from: session.end))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .leading)
                        Circle()
                            .fill(colors.color(session.bundleID))
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.appName).font(.callout)
                            if !session.details.isEmpty {
                                Text(session.details.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(Format.duration(session.duration))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }
}

struct UsageRow: View {
    let color: Color
    let name: String
    let seconds: TimeInterval
    let total: TimeInterval
    /// nil: nothing to expand; otherwise shows a disclosure chevron.
    var expanded: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).lineLimit(1).truncationMode(.middle)
                if let expanded {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(Format.duration(seconds)).monospacedDigit()
                Text(Format.percent(seconds, of: total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(color.opacity(0.75))
                    .frame(width: max(2, geometry.size.width * (total > 0 ? seconds / total : 0)))
            }
            .frame(height: 3)
        }
    }
}

struct EmptyNote: View {
    var text = "За этот период ничего не записано."

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }
}
