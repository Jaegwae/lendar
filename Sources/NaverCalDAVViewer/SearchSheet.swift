import SwiftUI

struct ScheduleSearchSheet: View {
    @ObservedObject var store: CalendarStore
    let onClose: () -> Void
    let onSelect: (CalendarItem) -> Void

    @State private var query = ""
    @State private var rangeStart: Date? = Calendar.current.startOfDay(for: Date())
    @State private var rangeEnd: Date? = Calendar.current.startOfDay(for: Date())
    @State private var showingStartPicker = false
    @State private var showingEndPicker = false

    private var filteredResults: [CalendarItem] {
        ScheduleSearchMatcher.filteredItems(store.items, query: query, range: searchRange)
    }

    var body: some View {
        GeometryReader { proxy in
            let modalWidth = min(700, max(320, proxy.size.width - 28))
            let modalHeight = min(560, max(360, proxy.size.height - 40))
            let compact = modalWidth < 500

            VStack(alignment: .leading, spacing: 14) {
                Text("일정 검색")
                    .font(CalendarDesign.displayFont(size: compact ? 26 : 32, weight: .semibold))
                    .tracking(-0.28)
                    .foregroundStyle(CalendarDesign.nearBlack)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CalendarDesign.textTertiary)
                        .calendarAnimatedIcon(rotation: -8, scale: 1.06)
                    TextField("일정 이름 검색", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .calendarGlassSurface(cornerRadius: 10, material: .ultraThinMaterial, tintOpacity: 0.24, shadowOpacity: 0.02)

                dateRangeFilterBar

                Text("검색 결과 \(filteredResults.count)개")
                    .font(CalendarDesign.textFont(size: 14, weight: .medium))
                    .tracking(-0.224)
                    .foregroundStyle(CalendarDesign.textSecondary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredResults) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(CalendarPalette.eventTint(for: item))
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(CalendarText.cleanName(item.summary))
                                            .font(CalendarDesign.textFont(size: 15, weight: .semibold))
                                            .tracking(-0.224)
                                            .foregroundStyle(CalendarDesign.nearBlack)
                                            .lineLimit(1)

                                        Text(CalendarFormatting.detailedEventRangeText(for: item))
                                            .font(CalendarDesign.textFont(size: 12, weight: .regular))
                                            .tracking(-0.12)
                                            .foregroundStyle(CalendarDesign.textSecondary)
                                            .lineLimit(1)

                                        Text(CalendarText.cleanName(item.sourceCalendar))
                                            .font(CalendarDesign.textFont(size: 11, weight: .regular))
                                            .tracking(-0.12)
                                            .foregroundStyle(CalendarDesign.textTertiary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CalendarDesign.subtleRowFill)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
                .calendarModalSectionSurface()
            }
            .padding(20)
            .frame(width: modalWidth, height: modalHeight)
            .calendarModalContainer()
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var dateRangeFilterBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("기간")
                    .font(CalendarDesign.textFont(size: 14, weight: .semibold))
                    .tracking(-0.224)
                    .foregroundStyle(CalendarDesign.nearBlack)

                Text(rangeSummary)
                    .font(CalendarDesign.textFont(size: 12, weight: .regular))
                    .tracking(-0.12)
                    .foregroundStyle(CalendarDesign.textTertiary)
            }

            HStack(spacing: 8) {
                datePill(
                    title: "시작",
                    date: effectiveRangeStart,
                    isPresented: $showingStartPicker
                ) { selected in
                    let selectedDay = Calendar.current.startOfDay(for: selected)
                    rangeStart = selectedDay
                    if selectedDay > effectiveRangeEnd {
                        rangeEnd = selectedDay
                    }
                }

                Rectangle()
                    .fill(CalendarDesign.divider)
                    .frame(width: 16, height: 1)

                datePill(
                    title: "종료",
                    date: effectiveRangeEnd,
                    isPresented: $showingEndPicker
                ) { selected in
                    let selectedDay = Calendar.current.startOfDay(for: selected)
                    rangeEnd = selectedDay
                    if selectedDay < effectiveRangeStart {
                        rangeStart = selectedDay
                    }
                }
            }

            HStack(spacing: 8) {
                presetChip("오늘", range: todayRange())
                presetChip("이번 주", range: thisWeekRange())
                presetChip("이번 달", range: thisMonthRange())
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .calendarGlassSurface(cornerRadius: 12, material: .ultraThinMaterial, tintOpacity: 0.20, shadowOpacity: 0.025)
    }

    private func datePill(
        title: String,
        date: Date,
        isPresented: Binding<Bool>,
        onSelect: @escaping (Date) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(CalendarDesign.textFont(size: 11, weight: .semibold))
                .tracking(-0.12)
                .foregroundStyle(CalendarDesign.textTertiary)

            Button {
                isPresented.wrappedValue = true
            } label: {
                HStack(spacing: 8) {
                    Text(CalendarFormatting.filterDate.string(from: date))
                        .font(CalendarDesign.textFont(size: 14, weight: .semibold))
                        .tracking(-0.224)
                        .foregroundStyle(CalendarDesign.nearBlack)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CalendarDesign.textTertiary)
                        .rotationEffect(.degrees(isPresented.wrappedValue ? 180 : 0))
                        .animation(.snappy(duration: 0.22, extraBounce: 0.04), value: isPresented.wrappedValue)
                        .calendarAnimatedIcon(yOffset: 1)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CalendarDesign.subtleRowFill)
                )
            }
            .buttonStyle(CalendarAnimatedIconButtonStyle())
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                CompactDatePickerPopover(
                    title: title,
                    selection: Binding(
                        get: { date },
                        set: { onSelect($0) }
                    ),
                    isPresented: isPresented
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calendarGlassSurface(cornerRadius: 10, material: .ultraThinMaterial, tintOpacity: 0.16, shadowOpacity: 0.015)
    }

    private func presetChip(_ title: String, range: (Date, Date)) -> some View {
        Button(title) {
            rangeStart = range.0
            rangeEnd = range.1
        }
        .buttonStyle(CalendarAnimatedIconButtonStyle())
        .font(CalendarDesign.textFont(size: 11, weight: .semibold))
        .foregroundStyle(CalendarDesign.linkBlue)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(CalendarDesign.appleBlue.opacity(0.10))
        )
    }

    private func todayRange() -> (Date, Date) {
        let range = ScheduleDateRange.today()
        return (range.start, range.end)
    }

    private func thisWeekRange() -> (Date, Date) {
        let range = ScheduleDateRange.thisWeek()
        return (range.start, range.end)
    }

    private func thisMonthRange() -> (Date, Date) {
        let range = ScheduleDateRange.thisMonth()
        return (range.start, range.end)
    }

    private var effectiveRangeStart: Date {
        rangeStart ?? Calendar.current.startOfDay(for: Date())
    }

    private var effectiveRangeEnd: Date {
        rangeEnd ?? effectiveRangeStart
    }

    private var searchRange: ScheduleDateRange {
        ScheduleDateRange(start: effectiveRangeStart, end: effectiveRangeEnd)
    }

    private var rangeSummary: String {
        let range = searchRange
        if Calendar.current.isDate(range.start, inSameDayAs: range.end) {
            return "\(CalendarFormatting.filterDate.string(from: range.start)) 하루"
        }
        return "\(CalendarFormatting.filterDate.string(from: range.start)) - \(CalendarFormatting.filterDate.string(from: range.end))"
    }
}
