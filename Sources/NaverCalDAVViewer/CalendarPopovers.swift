import SwiftUI

struct CalendarColorPalettePopover: View {
    let selectedCode: String
    let onSelect: (Color) -> Void

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("색상")
                .font(CalendarDesign.textFont(size: 13, weight: .semibold))
                .tracking(-0.224)
                .foregroundStyle(CalendarDesign.nearBlack)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(CalendarPalette.choices.enumerated()), id: \.offset) { _, option in
                    Button {
                        onSelect(option.color)
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isSelected(option.color) ? CalendarDesign.nearBlack : Color.white.opacity(0.84),
                                        lineWidth: isSelected(option.color) ? 2 : 1
                                    )
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .opacity(isSelected(option.color) ? 1 : 0)
                            )
                    }
                    .buttonStyle(CalendarAnimatedIconButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(width: 170)
        .calendarGlassSurface(cornerRadius: 14, material: .regularMaterial, tintOpacity: 0.20, shadowOpacity: 0.12)
    }

    private func isSelected(_ color: Color) -> Bool {
        CalendarPalette.customCode(for: color) == selectedCode
    }
}

struct MonthJumpPopover: View {
    let currentMonth: Date
    let onSelect: (Date) -> Void
    let onClose: () -> Void

    @State private var displayedYear: Int
    @State private var yearStep = 0
    @State private var monthGridOffset: CGFloat = 0
    @State private var monthGridOpacity: Double = 1
    @State private var yearFeedback = false

    private let monthColumns = Array(repeating: GridItem(.fixed(54), spacing: 6), count: 4)

    init(currentMonth: Date, onSelect: @escaping (Date) -> Void, onClose: @escaping () -> Void) {
        self.currentMonth = currentMonth
        self.onSelect = onSelect
        self.onClose = onClose
        _displayedYear = State(initialValue: Calendar.current.component(.year, from: currentMonth))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(verbatim: "\(displayedYear)")
                    .font(CalendarDesign.displayFont(size: 22, weight: .semibold))
                    .tracking(-0.28)
                    .foregroundStyle(CalendarDesign.nearBlack)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.24, extraBounce: 0.02), value: displayedYear)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(yearFeedback ? CalendarDesign.appleBlue.opacity(0.18) : Color.clear)
                    )
                    .scaleEffect(yearFeedback ? 1.08 : 1.0)
                    .animation(.snappy(duration: 0.20, extraBounce: 0.08), value: yearFeedback)

                Spacer()

                yearButton(systemName: "chevron.left") {
                    moveYear(by: -1)
                }

                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                        onSelect(Date())
                    }
                } label: {
                    Text("오늘")
                        .font(CalendarDesign.textFont(size: 12, weight: .semibold))
                        .tracking(-0.12)
                        .foregroundStyle(CalendarDesign.nearBlack)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CalendarDesign.lightGray)
                        )
                }
                .buttonStyle(CalendarAnimatedIconButtonStyle())

                yearButton(systemName: "chevron.right") {
                    moveYear(by: 1)
                }
            }

            LazyVGrid(columns: monthColumns, spacing: 6) {
                ForEach(1 ... 12, id: \.self) { month in
                    Button {
                        if let target = targetMonth(month) {
                            onSelect(target)
                        }
                    } label: {
                        Text("\(month)월")
                            .font(CalendarDesign.textFont(size: 13, weight: isSelected(month) ? .semibold : .medium))
                            .tracking(-0.12)
                            .foregroundStyle(isSelected(month) ? .white : CalendarDesign.nearBlack)
                            .frame(width: 54, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected(month) ? CalendarDesign.appleBlue : CalendarDesign.lightGray)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .offset(x: monthGridOffset)
            .opacity(monthGridOpacity)
        }
        .padding(14)
        .frame(width: 262)
        .calendarGlassSurface(cornerRadius: 14, material: .regularMaterial, tintOpacity: 0.20, shadowOpacity: 0.12)
    }

    private func yearButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CalendarDesign.textSecondary)
                .calendarAnimatedIcon(rotation: systemName.contains("left") ? -18 : 18, scale: 1.10)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(CalendarDesign.lightGray)
                )
        }
        .buttonStyle(CalendarAnimatedIconButtonStyle())
    }

    private func moveYear(by value: Int) {
        guard monthGridOpacity == 1 else { return }
        yearStep = value
        let outgoingOffset: CGFloat = value > 0 ? -56 : 56
        let incomingOffset: CGFloat = value > 0 ? 56 : -56

        withAnimation(.easeInOut(duration: 0.16)) {
            monthGridOffset = outgoingOffset
            monthGridOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            var noAnimation = Transaction()
            noAnimation.disablesAnimations = true

            withTransaction(noAnimation) {
                displayedYear += value
                yearFeedback = true
                monthGridOffset = incomingOffset
                monthGridOpacity = 0.0
            }

            DispatchQueue.main.async {
                withAnimation(.snappy(duration: 0.34, extraBounce: 0.05)) {
                    monthGridOffset = 0
                    monthGridOpacity = 1
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                withAnimation(.smooth(duration: 0.18)) {
                    yearFeedback = false
                }
            }
        }
    }

    private func targetMonth(_ month: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: displayedYear, month: month, day: 1))
    }

    private func isSelected(_ month: Int) -> Bool {
        Calendar.current.component(.year, from: currentMonth) == displayedYear &&
            Calendar.current.component(.month, from: currentMonth) == month
    }
}

struct CompactDatePickerPopover: View {
    let title: String
    @Binding var selection: Date
    @Binding var isPresented: Bool

    @State private var displayedMonth: Date

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: 7)
    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]

    init(title: String, selection: Binding<Date>, isPresented: Binding<Bool>) {
        self.title = title
        _selection = selection
        _isPresented = isPresented
        _displayedMonth = State(initialValue: Self.monthStart(for: selection.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CalendarDesign.textFont(size: 12, weight: .semibold))
                        .tracking(-0.12)
                        .foregroundStyle(CalendarDesign.textTertiary)

                    Text(CalendarFormatting.monthTitle.string(from: displayedMonth))
                        .font(CalendarDesign.textFont(size: 17, weight: .semibold))
                        .tracking(-0.374)
                        .foregroundStyle(CalendarDesign.nearBlack)
                }

                Spacer()

                monthButton(systemName: "chevron.left") {
                    moveMonth(by: -1)
                }
                monthButton(systemName: "chevron.right") {
                    moveMonth(by: 1)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(CalendarDesign.textFont(size: 11, weight: .semibold))
                        .tracking(-0.12)
                        .foregroundStyle(weekdayColor(index))
                        .frame(width: 32, height: 22)
                }

                ForEach(days, id: \.self) { date in
                    dayButton(for: date)
                }
            }
        }
        .padding(14)
        .frame(width: 276)
        .calendarGlassSurface(cornerRadius: 14, material: .regularMaterial, tintOpacity: 0.20, shadowOpacity: 0.10)
    }

    private func monthButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CalendarDesign.textSecondary)
                .calendarAnimatedIcon(rotation: systemName.contains("left") ? -18 : 18, scale: 1.10)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(CalendarDesign.lightGray)
                )
        }
        .buttonStyle(CalendarAnimatedIconButtonStyle())
    }

    private func dayButton(for date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selection)
        let today = Calendar.current.isDateInToday(date)
        let inMonth = Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month)

        return Button {
            selection = Calendar.current.startOfDay(for: date)
            isPresented = false
        } label: {
            Text(CalendarFormatting.dayNumber.string(from: date))
                .font(CalendarDesign.textFont(size: 12, weight: selected ? .semibold : .regular))
                .tracking(-0.12)
                .foregroundStyle(dayForeground(selected: selected, today: today, inMonth: inMonth))
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(dayBackground(selected: selected, today: today))
                )
        }
        .buttonStyle(.plain)
    }

    private var days: [Date] {
        let calendar = Calendar.current
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let firstCell = calendar.date(byAdding: .day, value: -(firstWeekday - 1), to: displayedMonth) ?? displayedMonth
        return (0 ..< 42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstCell) }
    }

    private func moveMonth(by offset: Int) {
        guard let nextMonth = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else {
            return
        }
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.01)) {
            displayedMonth = Self.monthStart(for: nextMonth)
        }
    }

    private func weekdayColor(_ index: Int) -> Color {
        if index == 0 { return Color.red.opacity(0.72) }
        if index == 6 { return CalendarDesign.linkBlue.opacity(0.78) }
        return CalendarDesign.textTertiary
    }

    private func dayForeground(selected: Bool, today: Bool, inMonth: Bool) -> Color {
        if selected { return .white }
        if today { return CalendarDesign.linkBlue }
        if !inMonth { return CalendarDesign.textTertiary.opacity(0.42) }
        return CalendarDesign.nearBlack
    }

    private func dayBackground(selected: Bool, today: Bool) -> Color {
        if selected { return CalendarDesign.appleBlue }
        if today { return CalendarDesign.appleBlue.opacity(0.10) }
        return .clear
    }

    private static func monthStart(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }
}
