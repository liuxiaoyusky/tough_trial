import Foundation
import SwiftUI
import ToughTrialV2Core

/// A shared iOS/macOS statistics surface over the capture store's ledger.
/// The core projection keeps date and currency rules out of the view.
struct V2LedgerStatisticsView: View {
    @ObservedObject var store: V2CaptureStore
    @State private var anchorDate = Date()
    @State private var period: V2LedgerStatistics.Period = .month

    private var projections: [V2LedgerStatistics.Projection] {
        V2LedgerStatistics.project(
            entries: store.state.ledger,
            categories: store.state.categories,
            anchor: anchorDate,
            period: period,
            calendar: .current
        )
    }

    var body: some View {
        List {
            Section {
                DatePicker("日期", selection: $anchorDate, displayedComponents: .date)
                    .accessibilityIdentifier("ledger.statistics.anchor")
                Picker("统计周期", selection: $period) {
                    ForEach(V2LedgerStatistics.Period.allCases, id: \.self) { value in
                        Text("自然\(value.label)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ledger.statistics.period")
            } header: {
                Text("统计范围")
            }

            if projections.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title2)
                            .foregroundStyle(V2Theme.secondary)
                        Text("还没有账单")
                            .font(.headline)
                        Text("先保存一笔账单，统计会按自然日、周、月或年显示。")
                            .font(.subheadline)
                            .foregroundStyle(V2Theme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                ForEach(projections) { projection in
                    projectionSections(projection)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(V2Theme.page)
        .navigationTitle("账单统计")
        .onAppear { store.refresh() }
    }

    @ViewBuilder
    private func projectionSections(_ projection: V2LedgerStatistics.Projection) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                statisticRow("收入", projection.totals.income, currency: projection.currency, color: .green)
                statisticRow("支出", projection.totals.expense, currency: projection.currency, color: V2Theme.orange)
                statisticRow("净额", projection.totals.net, currency: projection.currency,
                             color: projection.totals.net >= .zero ? V2Theme.mint : V2Theme.ColorRole.destructive)
            }
            .padding(.vertical, 4)
        } header: {
            Text(projection.currency)
        }

        if !projection.categoryTotals.isEmpty {
            Section {
                ForEach(projection.categoryTotals) { category in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(category.name)
                            Spacer()
                            Text(amount(category.net, currency: projection.currency))
                                .font(.body.monospacedDigit())
                        }
                        Text("收入 \(amount(category.income, currency: projection.currency)) · 支出 \(amount(category.expense, currency: projection.currency))")
                            .font(.caption)
                            .foregroundStyle(V2Theme.secondary)
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("已确认分类")
            }
        }

        if projection.unclassified.income != .zero || projection.unclassified.expense != .zero {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("分类仍需确认")
                    Text("收入 \(amount(projection.unclassified.income, currency: projection.currency)) · 支出 \(amount(projection.unclassified.expense, currency: projection.currency))")
                        .font(.caption)
                        .foregroundStyle(V2Theme.secondary)
                }
                .padding(.vertical, 3)
            } header: {
                Text("未确认分类")
            }
        }

        Section {
            if projection.dailyTotals.isEmpty {
                Text("所选\(projection.period.label)没有可按日期显示的账单。")
                    .foregroundStyle(V2Theme.secondary)
            } else {
                ForEach(projection.dailyTotals) { day in
                    HStack {
                        Text(day.localDate)
                        Spacer()
                        Text("收入 \(amount(day.income, currency: projection.currency))")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("支出 \(amount(day.expense, currency: projection.currency))")
                            .font(.caption)
                            .foregroundStyle(V2Theme.orange)
                    }
                }
            }
        } header: {
            Text("每日明细")
        }

        if projection.unknownDateCount > 0 {
            Section {
                    Text("全量有 \(projection.unknownDateCount) 笔账单没有有效消费日期，未计入任何自然周期；统计不会使用记录时间推定日期。")
                    .font(.caption)
                    .foregroundStyle(V2Theme.secondary)
            } header: {
                Text("全部日期未知")
            }
        }

        if projection.transferCount > 0 {
            Section {
                Text("全量有 \(projection.transferCount) 笔转账，均不计入收入、支出或净额。")
                    .font(.caption)
                    .foregroundStyle(V2Theme.secondary)
            } header: {
                Text("全部转账")
            }
        }
    }

    private func statisticRow(_ title: String, _ value: Decimal, currency: String, color: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(V2Theme.secondary)
            Spacer()
            Text(amount(value, currency: currency))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func amount(_ value: Decimal, currency: String) -> String {
        "\(currency) \(NSDecimalNumber(decimal: value).stringValue)"
    }
}
