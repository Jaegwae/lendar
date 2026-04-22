import SwiftUI

// Compact month picker retained for older navigation surfaces. The primary month
// jump popover currently lives in ContentView.
struct MiniMonthNavigatorView: View {
    @ObservedObject var store: CalendarStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(CalendarFormatting.monthTitle.string(from: store.displayedMonth))
                    .font(CalendarDesign.textFont(size: 17, weight: .semibold))
                    .tracking(-0.374)
                    .foregroundStyle(CalendarDesign.nearBlack)
                Spacer()
                Button(action: { store.moveMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .calendarAnimatedIcon(rotation: -18, scale: 1.10)
                }
                .buttonStyle(CalendarAnimatedIconButtonStyle())
                Button(action: { store.moveMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .calendarAnimatedIcon(rotation: 18, scale: 1.10)
                }
                .buttonStyle(CalendarAnimatedIconButtonStyle())
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(CalendarDesign.textFont(size: 11, weight: .semibold))
                        .tracking(-0.12)
                        .foregroundStyle(index == 0 ? Color.red.opacity(0.72) : CalendarDesign.textTertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(cells, id: \.self) { date in
                    Text(CalendarFormatting.dayNumber.string(from: date))
                        .font(.system(size: 11, weight: isSelected(date) ? .bold : .medium))
                        .tracking(-0.12)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(backgroundColor(for: date))
                        )
                        .foregroundStyle(foregroundColor(for: date))
                        .onTapGesture {
                            store.selectedDate = Calendar.current.startOfDay(for: date)
                            store.displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
                        }
                }
            }
        }
        .padding(16)
        .calendarGlassSurface(cornerRadius: 14, material: .thinMaterial, tintOpacity: 0.18, shadowOpacity: 0.08)
    }

    private var cells: [Date] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: store.displayedMonth)) ?? store.displayedMonth
        let weekday = calendar.component(.weekday, from: monthStart)
        let firstCell = calendar.date(byAdding: .day, value: -(weekday - 1), to: monthStart) ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstCell) }
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: store.selectedDate)
    }

    private func backgroundColor(for date: Date) -> Color {
        if isSelected(date) {
            return CalendarDesign.appleBlue
        }
        if Calendar.current.isDateInToday(date) {
            return CalendarDesign.appleBlue.opacity(0.10)
        }
        return .clear
    }

    private func foregroundColor(for date: Date) -> Color {
        if isSelected(date) {
            return .white
        }
        if !Calendar.current.isDate(date, equalTo: store.displayedMonth, toGranularity: .month) {
            return CalendarDesign.textTertiary.opacity(0.45)
        }
        if Calendar.current.component(.weekday, from: date) == 1 {
            return Color.red.opacity(0.76)
        }
        return CalendarDesign.nearBlack
    }
}
