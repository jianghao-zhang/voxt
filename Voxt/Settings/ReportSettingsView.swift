import SwiftUI

struct ReportSettingsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var historyStore: TranscriptionHistoryStore
    @State private var cachedSummary: ReportSummary?
    @State private var summaryGeneration = 0

    private let cardColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        let summary = cachedSummary ?? ReportSummary.empty(locale: locale)

        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: cardColumns, spacing: 12) {
                metricCard(
                    iconName: "clock.badge.checkmark",
                    titleKey: "Total Dictation Time",
                    value: formattedDuration(summary.totalDictationSeconds)
                )
                metricCard(
                    iconName: "character.textbox",
                    titleKey: "Total Dictation Characters",
                    value: localizedNumber(summary.totalCharacters),
                    unitKey: "chars"
                )
                metricCard(
                    iconName: "globe",
                    titleKey: "Total Translation Characters",
                    value: localizedNumber(summary.totalTranslationCharacters),
                    unitKey: "chars"
                )
                metricCard(
                    iconName: "speedometer",
                    titleKey: "Average Dictation Speed",
                    value: localizedNumber(Int(summary.averageCharactersPerMinute)),
                    unitKey: "char/min"
                )
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily Characters (Last 7 Days)")
                        .font(.headline)

                    SevenDayBarChart(data: summary.dailyCharacters)
                        .frame(height: 240)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshSummary)
        .onReceive(historyStore.$entries) { _ in
            refreshSummary()
        }
        .onChange(of: locale.identifier) { _, _ in
            refreshSummary()
        }
    }

    @ViewBuilder
    private func metricCard(
        iconName: String,
        titleKey: LocalizedStringKey,
        value: String,
        unitKey: LocalizedStringKey? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(titleKey)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let unitKey {
                    Text(unitKey)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainSeconds = totalSeconds % 60
        if hours > 0 {
            let format = NSLocalizedString("%dh %dm", comment: "")
            return String(format: format, locale: locale, hours, minutes)
        }
        if minutes > 0 {
            let format = NSLocalizedString("%dm %ds", comment: "")
            return String(format: format, locale: locale, minutes, remainSeconds)
        }
        let format = NSLocalizedString("%d s", comment: "")
        return String(format: format, locale: locale, remainSeconds)
    }

    private func localizedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func refreshSummary() {
        summaryGeneration += 1
        let generation = summaryGeneration
        let locale = locale
        let dayStarts = ReportSummary.lastSevenDayStarts()

        historyStore.reportMetrics(dayStarts: dayStarts) { metrics in
            guard generation == summaryGeneration else { return }
            cachedSummary = ReportSummary(
                metrics: metrics ?? .empty(dayStarts: dayStarts),
                locale: locale
            )
        }
    }
}

private struct SevenDayBarChart: View {
    struct DayValue: Identifiable {
        let dayStart: Date
        let label: String
        let value: Int

        var id: Date { dayStart }
    }

    let data: [DayValue]

    var body: some View {
        let maxValue = max(data.map(\.value).max() ?? 0, 1)
        let chartHeight: CGFloat = 150

        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(data) { item in
                    let minBarHeight: CGFloat = item.value > 0 ? 6 : 2
                    let scaledHeight = CGFloat(item.value) / CGFloat(maxValue) * chartHeight
                    let barHeight = max(minBarHeight, scaledHeight)

                    VStack(spacing: 6) {
                        Text("\(item.value)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight)

                        Text(item.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct ReportSummary {
    let totalDictationSeconds: TimeInterval
    let totalCharacters: Int
    let totalTranslationCharacters: Int
    let averageCharactersPerMinute: Double
    let dailyCharacters: [SevenDayBarChart.DayValue]

    init(metrics: HistoryReportMetrics, locale: Locale) {
        totalDictationSeconds = metrics.totalDictationSeconds
        totalCharacters = metrics.totalCharacters
        totalTranslationCharacters = metrics.totalTranslationCharacters
        averageCharactersPerMinute = totalDictationSeconds > 0
            ? Double(totalCharacters) / (totalDictationSeconds / 60.0)
            : 0
        dailyCharacters = Self.dailyCharacters(from: metrics.dailyCharacters, locale: locale)
    }

    static func empty(locale: Locale) -> ReportSummary {
        let dayStarts = lastSevenDayStarts()
        return ReportSummary(metrics: .empty(dayStarts: dayStarts), locale: locale)
    }

    static func lastSevenDayStarts() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDay)
        }
    }

    private static func dailyCharacters(from valuesByDay: [Date: Int], locale: Locale) -> [SevenDayBarChart.DayValue] {
        lastSevenDayStarts().map { day in
            return SevenDayBarChart.DayValue(
                dayStart: day,
                label: day.formatted(.dateTime.weekday(.abbreviated).locale(locale)),
                value: valuesByDay[day, default: 0]
            )
        }
    }
}

private extension HistoryReportMetrics {
    static func empty(dayStarts: [Date]) -> HistoryReportMetrics {
        HistoryReportMetrics(
            totalDictationSeconds: 0,
            totalCharacters: 0,
            totalTranslationCharacters: 0,
            dailyCharacters: Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, 0) })
        )
    }
}
