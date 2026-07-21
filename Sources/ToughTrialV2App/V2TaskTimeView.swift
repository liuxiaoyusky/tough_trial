import Foundation
import SwiftUI
import ToughTrialV2Core

struct V2TimeLensView: View {
    @Binding var scale: V2TaskTimeScale
    @Binding var anchor: Date
    let scheduledTasks: [V2ScheduledTask]
    let activeTaskIDs: Set<String>

    @State private var selectedScheduleID: String?

    var body: some View {
        VStack(spacing: 0) {
            scalePicker
                .padding(.horizontal, 18)

            periodBar

            calendarSurface
                .id("\(scale.rawValue)-\(Int(anchor.timeIntervalSinceReferenceDate))")
                .transition(.opacity.combined(with: .offset(y: 3)))
        }
        .overlay(alignment: .bottomLeading) {
            if let selectedTask {
                V2ScheduleSelectionBar(item: selectedTask)
                    .padding(.leading, 14)
                    .padding(.trailing, 82)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: scale) {
            selectedScheduleID = nil
        }
    }

    private var scalePicker: some View {
        HStack(spacing: 0) {
            ForEach(V2TaskTimeScale.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        scale = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(V2Theme.TypeRole.labelMedium)
                        .foregroundStyle(
                            scale == item
                                ? V2Theme.ColorRole.primary
                                : V2Theme.ColorRole.textTertiary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(scale == item ? V2Theme.ColorRole.primary : Color.clear)
                                .frame(width: 22, height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("time-scale-\(item.rawValue)")
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(V2Theme.ColorRole.outline)
                .frame(height: 1)
        }
    }

    private var periodBar: some View {
        HStack(spacing: 8) {
            Button {
                shiftPeriod(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V2Theme.ColorRole.textSecondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一时间段")

            Text(periodTitle)
                .font(V2Theme.TypeRole.titleMedium)
                .foregroundStyle(V2Theme.ColorRole.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("今天") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    anchor = V2TaskCalendar.startOfDay(Date())
                }
            }
            .font(V2Theme.TypeRole.labelSmall)
            .foregroundStyle(V2Theme.ColorRole.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                V2Theme.ColorRole.primaryContainer,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .buttonStyle(.plain)

            Button {
                shiftPeriod(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V2Theme.ColorRole.textSecondary)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一时间段")
        }
        .padding(.horizontal, 10)
        .frame(height: 58)
    }

    @ViewBuilder
    private var calendarSurface: some View {
        switch scale {
        case .year:
            V2YearScheduleView(anchor: anchor, scheduledTasks: scheduledTasks)
        case .month:
            V2MonthScheduleView(
                anchor: anchor,
                scheduledTasks: scheduledTasks,
                onSelect: select
            )
        case .week, .threeDay, .day:
            V2ScheduleGridView(
                dates: visibleDates,
                scheduledTasks: scheduledTasks,
                activeTaskIDs: activeTaskIDs,
                onSelect: select
            )
        }
    }

    private var visibleDates: [Date] {
        switch scale {
        case .week:
            let start = V2TaskCalendar.startOfWeek(anchor)
            return (0..<7).map { V2TaskCalendar.addingDays($0, to: start) }
        case .threeDay:
            return (0..<3).map { V2TaskCalendar.addingDays($0, to: anchor) }
        case .day:
            return [V2TaskCalendar.startOfDay(anchor)]
        case .year, .month:
            return []
        }
    }

    private var selectedTask: V2ScheduledTask? {
        guard let selectedScheduleID else { return nil }
        return scheduledTasks.first { $0.id == selectedScheduleID }
    }

    private var periodTitle: String {
        switch scale {
        case .year:
            return "\(V2TaskCalendar.component(.year, from: anchor))年"
        case .month:
            return "\(V2TaskCalendar.component(.year, from: anchor))年\(V2TaskCalendar.component(.month, from: anchor))月"
        case .week:
            guard let first = visibleDates.first, let last = visibleDates.last else { return "" }
            return "\(V2TaskCalendar.shortDate(first)) - \(V2TaskCalendar.shortDate(last))"
        case .threeDay:
            guard let last = visibleDates.last else { return V2TaskCalendar.shortDate(anchor) }
            return "\(V2TaskCalendar.shortDate(anchor)) - \(V2TaskCalendar.shortDate(last))"
        case .day:
            return "\(V2TaskCalendar.shortDate(anchor)) 周\(V2TaskCalendar.weekdayLabel(anchor))"
        }
    }

    private func shiftPeriod(_ direction: Int) {
        let component: Calendar.Component
        let amount: Int
        switch scale {
        case .year:
            component = .year
            amount = direction
        case .month:
            component = .month
            amount = direction
        case .week:
            component = .day
            amount = direction * 7
        case .threeDay:
            component = .day
            amount = direction * 3
        case .day:
            component = .day
            amount = direction
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            anchor = V2TaskCalendar.adding(component, value: amount, to: anchor)
            selectedScheduleID = nil
        }
    }

    private func select(_ item: V2ScheduledTask) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedScheduleID = item.id
        }
    }
}

private struct V2MonthScheduleView: View {
    let anchor: Date
    let scheduledTasks: [V2ScheduledTask]
    let onSelect: (V2ScheduledTask) -> Void

    private let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(V2Theme.ColorRole.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(V2Theme.ColorRole.outline.opacity(0.65)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(V2Theme.ColorRole.outline).frame(height: 1)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(V2TaskCalendar.monthGridDates(containing: anchor), id: \.self) { date in
                        V2MonthDayCell(
                            date: date,
                            isInMonth: V2TaskCalendar.isSameMonth(date, anchor),
                            tasks: V2TaskCalendar.tasks(on: date, from: scheduledTasks),
                            onSelect: onSelect
                        )
                    }
                }
                .padding(.bottom, 84)
            }
        }
    }
}

private struct V2MonthDayCell: View {
    let date: Date
    let isInMonth: Bool
    let tasks: [V2ScheduledTask]
    let onSelect: (V2ScheduledTask) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text("\(V2TaskCalendar.component(.day, from: date))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(dayNumberColor)
                .frame(width: 24, height: 24)
                .background(dayNumberBackground, in: Circle())

            ForEach(Array(tasks.prefix(2))) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(item.isDone ? V2Theme.ColorRole.textTertiary : V2Theme.ColorRole.textSecondary)
                        .lineLimit(1)
                        .strikethrough(item.isDone, color: V2Theme.ColorRole.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 3)
                        .frame(height: 16)
                        .background(monthEventBackground(item), in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
            }

            if tasks.count > 2 {
                HStack(spacing: 3) {
                    ForEach(0..<min(3, tasks.count - 2), id: \.self) { _ in
                        Circle()
                            .fill(V2Theme.ColorRole.textTertiary)
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(height: 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.top, 5)
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .overlay(alignment: .trailing) {
            Rectangle().fill(V2Theme.ColorRole.outline.opacity(0.48)).frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(V2Theme.ColorRole.outline.opacity(0.48)).frame(height: 1)
        }
    }

    private var dayNumberColor: Color {
        if V2TaskCalendar.isToday(date) { return V2Theme.ColorRole.onPrimary }
        return isInMonth ? V2Theme.ColorRole.textSecondary : V2Theme.ColorRole.outline
    }

    private var dayNumberBackground: Color {
        V2TaskCalendar.isToday(date) ? V2Theme.ColorRole.primary : Color.clear
    }

    private func monthEventBackground(_ item: V2ScheduledTask) -> Color {
        item.isDone ? V2Theme.ColorRole.taskCompleteContainer : V2Theme.ColorRole.surfaceMuted
    }
}

private struct V2YearScheduleView: View {
    let anchor: Date
    let scheduledTasks: [V2ScheduledTask]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(0..<12, id: \.self) { monthOffset in
                    let month = V2TaskCalendar.month(monthOffset + 1, inYearOf: anchor)
                    V2MiniMonthView(
                        month: month,
                        scheduledTasks: scheduledTasks
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
    }
}

private struct V2MiniMonthView: View {
    let month: Date
    let scheduledTasks: [V2ScheduledTask]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(V2TaskCalendar.component(.month, from: month))月")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V2Theme.ColorRole.textSecondary)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(V2TaskCalendar.monthGridDates(containing: month), id: \.self) { date in
                    let isInMonth = V2TaskCalendar.isSameMonth(date, month)
                    let tasks = V2TaskCalendar.tasks(on: date, from: scheduledTasks)
                    Text(isInMonth ? "\(V2TaskCalendar.component(.day, from: date))" : "")
                        .font(.system(size: 6.5, weight: .medium))
                        .foregroundStyle(V2TaskCalendar.isToday(date) ? V2Theme.ColorRole.onPrimary : V2Theme.ColorRole.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 11)
                        .background(V2TaskCalendar.isToday(date) ? V2Theme.ColorRole.primary : Color.clear, in: Circle())
                        .overlay(alignment: .bottom) {
                            if isInMonth, !tasks.isEmpty, !V2TaskCalendar.isToday(date) {
                                Circle()
                                    .fill(tasks.allSatisfy(\.isDone) ? V2Theme.ColorRole.taskComplete : V2Theme.ColorRole.primary)
                                    .frame(width: 2, height: 2)
                                    .offset(y: 2)
                            }
                        }
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V2Theme.ColorRole.outline).frame(height: 1)
        }
    }
}

private struct V2ScheduleGridView: View {
    let dates: [Date]
    let scheduledTasks: [V2ScheduledTask]
    let activeTaskIDs: Set<String>
    let onSelect: (V2ScheduledTask) -> Void

    var body: some View {
        GeometryReader { proxy in
            let gutter = dates.count == 1 ? 50.0 : 44.0
            let dayWidth = max(1, (proxy.size.width - gutter) / CGFloat(dates.count))

            VStack(spacing: 0) {
                dayHeader(gutter: gutter, dayWidth: dayWidth)
                allDayRail(gutter: gutter, dayWidth: dayWidth)

                ScrollView(.vertical, showsIndicators: false) {
                    V2ScheduleTimeline(
                        dates: dates,
                        scheduledTasks: scheduledTasks,
                        activeTaskIDs: activeTaskIDs,
                        gutter: gutter,
                        dayWidth: dayWidth,
                        onSelect: onSelect
                    )
                    .padding(.bottom, 86)
                }
            }
        }
    }

    private func dayHeader(gutter: CGFloat, dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: gutter, height: 48)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(V2Theme.ColorRole.outline.opacity(0.55)).frame(width: 1)
                }

            ForEach(dates, id: \.self) { date in
                VStack(spacing: 2) {
                    Text("周\(V2TaskCalendar.weekdayLabel(date))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(V2TaskCalendar.isToday(date) ? V2Theme.ColorRole.primary : V2Theme.ColorRole.textTertiary)

                    Text("\(V2TaskCalendar.component(.day, from: date))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V2TaskCalendar.isToday(date) ? V2Theme.ColorRole.onPrimary : V2Theme.ColorRole.textSecondary)
                        .frame(width: 25, height: 25)
                        .background(V2TaskCalendar.isToday(date) ? V2Theme.ColorRole.primary : Color.clear, in: Circle())
                }
                .frame(width: dayWidth, height: 48)
            }
        }
        .frame(height: 48)
        .overlay(alignment: .top) {
            Rectangle().fill(V2Theme.ColorRole.outline.opacity(0.60)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(V2Theme.ColorRole.outline).frame(height: 1)
        }
    }

    private func allDayRail(gutter: CGFloat, dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("全天")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(V2Theme.ColorRole.textTertiary)
                .frame(width: gutter, height: 38)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(V2Theme.ColorRole.outline.opacity(0.55)).frame(width: 1)
                }

            ForEach(dates, id: \.self) { date in
                let items = V2TaskCalendar.tasks(on: date, from: scheduledTasks).filter(\.isAllDay)
                ZStack(alignment: .leading) {
                    if let first = items.first {
                        Button {
                            onSelect(first)
                        } label: {
                            Text(first.title)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(first.isDone ? V2Theme.ColorRole.textTertiary : V2Theme.ColorRole.textSecondary)
                                .lineLimit(1)
                                .strikethrough(first.isDone, color: V2Theme.ColorRole.textTertiary)
                                .padding(.horizontal, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 27)
                                .background(
                                    first.isDone
                                        ? V2Theme.ColorRole.taskCompleteContainer
                                        : V2Theme.ColorRole.primaryContainer,
                                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 2)
                    }

                    if items.count > 1 {
                        Text("+\(items.count - 1)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(V2Theme.ColorRole.primary)
                            .padding(.horizontal, 4)
                            .frame(height: 16)
                            .background(V2Theme.ColorRole.surfaceRaised, in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 3)
                    }
                }
                .frame(width: dayWidth, height: 38)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(V2Theme.ColorRole.outline.opacity(0.42)).frame(width: 1)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(V2Theme.ColorRole.outline).frame(height: 1)
        }
    }
}

private struct V2ScheduleTimeline: View {
    let dates: [Date]
    let scheduledTasks: [V2ScheduledTask]
    let activeTaskIDs: Set<String>
    let gutter: CGFloat
    let dayWidth: CGFloat
    let onSelect: (V2ScheduledTask) -> Void

    private let startHour = 8
    private let endHour = 22
    private let hourHeight = 44.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            gridLines

            ForEach(startHour...endHour, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(V2Theme.ColorRole.textTertiary)
                    .frame(width: gutter - 7, alignment: .trailing)
                    .offset(y: hour == startHour ? 2 : CGFloat(hour - startHour) * hourHeight - 6)
            }

            ForEach(timedTasks) { item in
                if let dayIndex = dates.firstIndex(where: { V2TaskCalendar.isSameDay($0, item.date) }),
                   let placement = item.timedPlacement {
                    let overlap = overlapMetrics(for: item, on: item.date)
                    let availableWidth = max(18, dayWidth - 4)
                    let eventWidth = availableWidth / CGFloat(overlap.count)
                    let x = gutter
                        + CGFloat(dayIndex) * dayWidth
                        + 2
                        + CGFloat(overlap.index) * eventWidth
                    let y = CGFloat(placement.startMinute - startHour * 60) / 60 * hourHeight + 2
                    let height = max(22, CGFloat(placement.durationMinutes) / 60 * hourHeight - 4)

                    V2TimeEventBlock(
                        item: item,
                        isActive: item.taskID.map(activeTaskIDs.contains) ?? false,
                        compactness: dates.count
                    ) {
                        onSelect(item)
                    }
                    .frame(width: max(16, eventWidth - 2), height: height)
                    .offset(x: x, y: y)
                }
            }

            if let nowMetrics {
                HStack(spacing: 0) {
                    Circle()
                        .fill(V2Theme.ColorRole.primary)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(V2Theme.ColorRole.primary)
                        .frame(height: 1)
                }
                .frame(width: dayWidth + 4)
                .offset(x: nowMetrics.x - 4, y: nowMetrics.y - 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: CGFloat(endHour - startHour) * hourHeight)
    }

    private var gridLines: some View {
        Canvas { context, size in
            var path = Path()
            for hour in 0...(endHour - startHour) {
                let y = CGFloat(hour) * hourHeight
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for day in 0...dates.count {
                let x = gutter + CGFloat(day) * dayWidth
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(V2Theme.ColorRole.outline.opacity(0.52)), lineWidth: 0.65)
        }
    }

    private var timedTasks: [V2ScheduledTask] {
        scheduledTasks.filter { item in
            item.timedPlacement != nil
                && dates.contains { V2TaskCalendar.isSameDay($0, item.date) }
        }
    }

    private func overlapMetrics(for item: V2ScheduledTask, on date: Date) -> (index: Int, count: Int) {
        guard let placement = item.timedPlacement else { return (0, 1) }
        let matching = timedTasks
            .filter { candidate in
                guard V2TaskCalendar.isSameDay(candidate.date, date),
                      let other = candidate.timedPlacement else { return false }
                let itemEnd = placement.startMinute + placement.durationMinutes
                let otherEnd = other.startMinute + other.durationMinutes
                return placement.startMinute < otherEnd && other.startMinute < itemEnd
            }
            .sorted { lhs, rhs in
                let left = lhs.timedPlacement?.startMinute ?? 0
                let right = rhs.timedPlacement?.startMinute ?? 0
                return left == right ? lhs.id < rhs.id : left < right
            }
        return (matching.firstIndex(where: { $0.id == item.id }) ?? 0, max(1, matching.count))
    }

    private var nowMetrics: (x: CGFloat, y: CGFloat)? {
        let now = Date()
        guard let dayIndex = dates.firstIndex(where: { V2TaskCalendar.isSameDay($0, now) }) else { return nil }
        let minutes = V2TaskCalendar.component(.hour, from: now) * 60 + V2TaskCalendar.component(.minute, from: now)
        guard minutes >= startHour * 60, minutes <= endHour * 60 else { return nil }
        return (
            gutter + CGFloat(dayIndex) * dayWidth,
            CGFloat(minutes - startHour * 60) / 60 * hourHeight
        )
    }
}

private struct V2TimeEventBlock: View {
    let item: V2ScheduledTask
    let isActive: Bool
    let compactness: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(accent.opacity(0.14), lineWidth: 1)
                    )

                Rectangle()
                    .fill(accent)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(item.isDone ? V2Theme.ColorRole.textTertiary : textColor)
                        .lineLimit(compactness == 1 ? 2 : 1)
                        .minimumScaleFactor(0.72)
                        .strikethrough(item.isDone, color: V2Theme.ColorRole.textTertiary)

                    if let placement = item.timedPlacement {
                        Text(V2TaskCalendar.timeLabel(placement.startMinute))
                            .font(.system(size: max(7, titleSize - 2), weight: .medium))
                            .foregroundStyle(V2Theme.ColorRole.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 3)
                .padding(.vertical, 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title)，\(item.timeAccessibilityLabel)")
    }

    private var titleSize: CGFloat {
        switch compactness {
        case 1: 12
        case 3: 11
        default: 9
        }
    }

    private var accent: Color {
        if item.isDone { return V2Theme.ColorRole.taskComplete }
        return V2Theme.ColorRole.primary
    }

    private var background: Color {
        if item.isDone { return V2Theme.ColorRole.taskCompleteContainer }
        if isActive { return V2Theme.ColorRole.primaryContainer }
        return V2Theme.ColorRole.surfaceRaised
    }

    private var textColor: Color {
        isActive ? V2Theme.ColorRole.onPrimaryContainer : V2Theme.ColorRole.textPrimary
    }
}

private struct V2ScheduleSelectionBar: View {
    let item: V2ScheduledTask

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(item.isDone ? V2Theme.ColorRole.taskComplete : V2Theme.ColorRole.primary)
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(V2Theme.TypeRole.labelMedium)
                    .foregroundStyle(V2Theme.ColorRole.textPrimary)
                    .lineLimit(1)

                Text(item.selectionLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(V2Theme.ColorRole.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 50)
        .background(V2Theme.ColorRole.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(V2Theme.ColorRole.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: V2Theme.ColorRole.textPrimary.opacity(0.10), radius: 18, y: 8)
    }
}

private enum V2TaskCalendar {
    static var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfWeek(_ date: Date) -> Date {
        let weekday = component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        return addingDays(-daysFromMonday, to: startOfDay(date))
    }

    static func addingDays(_ value: Int, to date: Date) -> Date {
        adding(.day, value: value, to: date)
    }

    static func adding(_ component: Calendar.Component, value: Int, to date: Date) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    static func component(_ component: Calendar.Component, from date: Date) -> Int {
        calendar.component(component, from: date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        component(.year, from: lhs) == component(.year, from: rhs)
            && component(.month, from: lhs) == component(.month, from: rhs)
    }

    static func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    static func weekdayLabel(_ date: Date) -> String {
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let index = (component(.weekday, from: date) + 5) % 7
        return labels[index]
    }

    static func shortDate(_ date: Date) -> String {
        "\(component(.month, from: date))月\(component(.day, from: date))日"
    }

    static func month(_ month: Int, inYearOf date: Date) -> Date {
        let year = component(.year, from: date)
        return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? date
    }

    static func monthGridDates(containing date: Date) -> [Date] {
        let monthStart = calendar.date(
            from: DateComponents(
                year: component(.year, from: date),
                month: component(.month, from: date),
                day: 1
            )
        ) ?? date
        let gridStart = startOfWeek(monthStart)
        return (0..<42).map { addingDays($0, to: gridStart) }
    }

    static func tasks(on date: Date, from tasks: [V2ScheduledTask]) -> [V2ScheduledTask] {
        tasks
            .filter { isSameDay($0.date, date) }
            .sorted { lhs, rhs in
                switch (lhs.placement, rhs.placement) {
                case (.allDay, .timed):
                    return true
                case (.timed, .allDay):
                    return false
                case let (.timed(left, _), .timed(right, _)):
                    return left == right ? lhs.id < rhs.id : left < right
                case (.allDay, .allDay):
                    return lhs.id < rhs.id
                }
            }
    }

    static func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

private extension V2ScheduledTask {
    var isAllDay: Bool {
        if case .allDay = placement { return true }
        return false
    }

    var timedPlacement: (startMinute: Int, durationMinutes: Int)? {
        if case let .timed(startMinute, durationMinutes) = placement {
            return (startMinute, durationMinutes)
        }
        return nil
    }

    var timeAccessibilityLabel: String {
        if isAllDay { return "全天" }
        guard let timedPlacement else { return "" }
        return V2TaskCalendar.timeLabel(timedPlacement.startMinute)
    }

    var selectionLabel: String {
        let dateLabel = "\(V2TaskCalendar.component(.year, from: date))-\(String(format: "%02d", V2TaskCalendar.component(.month, from: date)))-\(String(format: "%02d", V2TaskCalendar.component(.day, from: date)))"
        return "\(dateLabel) · \(timeAccessibilityLabel)"
    }
}
