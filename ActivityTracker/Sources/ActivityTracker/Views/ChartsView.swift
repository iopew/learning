import Charts
import SwiftUI
import ActivityCore

/// Minutes per hour of one day, stacked by app.
struct HourlyChart: View {
    let slices: [HourSlice]
    let colors: AppColors
    var height: CGFloat = 130

    private static let hours = (0..<24).map { String(format: "%02d", $0) }

    var body: some View {
        Chart(slices) { slice in
            BarMark(
                x: .value("Час", Self.hours[slice.hour]),
                y: .value("Минуты", slice.seconds / 60)
            )
            .foregroundStyle(colors.color(slice.bundleID))
        }
        .chartXScale(domain: Self.hours)
        .chartXAxis {
            AxisMarks(values: stride(from: 0, to: 24, by: 3).map { Self.hours[$0] })
        }
        .chartYScale(domain: 0.0...60.0)
        .chartYAxis {
            AxisMarks(values: [0.0, 15.0, 30.0, 45.0, 60.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) { Text("\(Int(minutes))м") }
                }
            }
        }
        .frame(height: height)
    }
}

/// Active time per day (or per week for long periods) with the daily average as a dashed line.
struct RangeChart: View {
    let report: Report
    var height: CGFloat = 150

    var body: some View {
        let unit: Calendar.Component = report.bucketUnit == .day ? .day : .weekOfYear
        VStack(alignment: .leading, spacing: 4) {
            Text(report.bucketUnit == .day ? "Часов в день" : "Часов в неделю")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(report.buckets) { bucket in
                    BarMark(
                        x: .value("Дата", bucket.start, unit: unit),
                        y: .value("Часы", bucket.seconds / 3600)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                if report.bucketUnit == .day && report.activeDays > 0 {
                    RuleMark(y: .value("Среднее", report.averagePerActiveDay / 3600))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text(Self.axisLabel(hours)) }
                    }
                }
            }
            .frame(height: height)
        }
    }

    private static func axisLabel(_ hours: Double) -> String {
        if hours == hours.rounded() { return "\(Int(hours))ч" }
        return "\(Int((hours * 60).rounded()))м"
    }
}

/// Every minute of the day as a cell: 24 rows (hours) × 60 columns (minutes), colored by the app that
/// dominated that minute. Hover shows what it was.
struct MinuteGrid: View {
    let minutes: [MinuteCell?]
    let colors: AppColors
    var rowHeight: CGFloat = 7

    @State private var hovered: Int?
    private let labelWidth: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Каждая минута дня")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(hoverText)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }
            GeometryReader { geometry in
                let cellWidth = (geometry.size.width - labelWidth) / 60
                Canvas { context, _ in
                    for hour in 0..<24 {
                        let y = CGFloat(hour) * rowHeight
                        if hour % 3 == 0 {
                            context.draw(
                                Text(String(format: "%02d", hour)).font(.system(size: min(10, rowHeight))).foregroundColor(.secondary),
                                at: CGPoint(x: 0, y: y + rowHeight / 2), anchor: .leading)
                        }
                        for minute in 0..<60 {
                            let index = hour * 60 + minute
                            let rect = CGRect(x: labelWidth + CGFloat(minute) * cellWidth, y: y + 0.5,
                                              width: max(1, cellWidth - 0.6), height: rowHeight - 1)
                            let color = index < minutes.count ? minutes[index].map { colors.color($0.bundleID) } : nil
                            let isHovered = index == hovered
                            context.fill(Path(rect), with: .color(isHovered ? .primary : color ?? Color.gray.opacity(0.12)))
                        }
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let hour = Int(point.y / rowHeight)
                        let minute = Int((point.x - labelWidth) / cellWidth)
                        hovered = (0..<24).contains(hour) && (0..<60).contains(minute) ? hour * 60 + minute : nil
                    case .ended:
                        hovered = nil
                    }
                }
            }
            .frame(height: rowHeight * 24)
        }
    }

    private var hoverText: String {
        guard let hovered else { return "наведите на клетку" }
        let time = String(format: "%02d:%02d", hovered / 60, hovered % 60)
        guard hovered < minutes.count, let cell = minutes[hovered] else { return "\(time) · —" }
        return "\(time) · \(cell.appName) · \(Format.duration(cell.seconds))"
    }
}
