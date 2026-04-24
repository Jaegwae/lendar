import SwiftUI

struct DayAgendaSheet: View {
    let date: Date
    let items: [CalendarItem]
    @Binding var selectedItem: CalendarItem?
    let onClose: () -> Void
    let onOpenDetail: (CalendarItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            let modalWidth = min(600, max(320, proxy.size.width - 28))
            let modalHeight = min(500, max(360, proxy.size.height - 40))
            let compact = modalWidth < 470

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(CalendarFormatting.dayHeader.string(from: date))
                            .font(CalendarDesign.displayFont(size: compact ? 22 : 26, weight: .semibold))
                            .tracking(-0.28)
                            .foregroundStyle(CalendarDesign.nearBlack)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(daySummary)
                            .font(CalendarDesign.textFont(size: 13, weight: .medium))
                            .tracking(-0.224)
                            .foregroundStyle(CalendarDesign.textSecondary)
                    }

                    Spacer()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            DayEventCard(item: item, day: date, isSelected: selectedItem?.id == item.id, compact: compact)
                                .onTapGesture {
                                    selectedItem = item
                                    onOpenDetail(item)
                                }

                            if item.id != items.last?.id {
                                Divider()
                                    .overlay(CalendarDesign.divider)
                                    .padding(.leading, compact ? 0 : 124)
                            }
                        }

                        if items.isEmpty {
                            VStack(spacing: 8) {
                                Text("일정 없음")
                                    .font(CalendarDesign.textFont(size: 16, weight: .semibold))
                                    .tracking(-0.224)
                                    .foregroundStyle(CalendarDesign.nearBlack)

                                Text("선택한 날짜에 표시할 일정이 없습니다.")
                                    .font(CalendarDesign.textFont(size: 13))
                                    .tracking(-0.224)
                                    .foregroundStyle(CalendarDesign.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 72)
                        }
                    }
                    .padding(.vertical, items.isEmpty ? 0 : 6)
                }
                .calendarModalSectionSurface()
            }
            .padding(20)
            .frame(width: modalWidth, height: modalHeight)
            .calendarModalContainer()
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var daySummary: String {
        if items.isEmpty {
            return "표시할 일정 없음"
        }
        return "\(items.count)개 일정"
    }
}

private struct DayEventCard: View {
    let item: CalendarItem
    let day: Date
    let isSelected: Bool
    let compact: Bool

    var body: some View {
        HStack(alignment: compact ? .center : .top, spacing: compact ? 9 : 13) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(timeTitle)
                    .font(CalendarDesign.textFont(size: compact ? 11 : 13, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(item.isCompleted ? CalendarDesign.textTertiary : CalendarDesign.nearBlack)
                    .lineLimit(1)

                if !timeSubtitle.isEmpty {
                    Text(timeSubtitle)
                        .font(CalendarDesign.textFont(size: compact ? 10 : 11, weight: .regular))
                        .tracking(-0.12)
                        .foregroundStyle(CalendarDesign.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: compact ? 58 : 84, alignment: .trailing)

            Circle()
                .fill(eventColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(CalendarText.cleanName(item.summary))
                        .font(CalendarDesign.textFont(size: compact ? 13 : 15, weight: .semibold))
                        .tracking(-0.224)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if item.isCompleted {
                        Text("완료")
                            .font(CalendarDesign.textFont(size: 11, weight: .semibold))
                            .tracking(-0.12)
                            .foregroundStyle(CalendarDesign.textTertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CalendarDesign.lightGray)
                            )
                    }
                }

                Text(metaText)
                    .font(CalendarDesign.textFont(size: compact ? 11 : 12))
                    .tracking(-0.12)
                    .foregroundStyle(CalendarDesign.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 9 : 12)
        .contentShape(Rectangle())
        .background(isSelected ? CalendarDesign.appleBlue.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var eventColor: Color {
        CalendarPalette.eventTint(for: item).opacity(item.isCompleted ? 0.48 : 1.0)
    }

    private var titleColor: Color {
        item.isCompleted ? CalendarDesign.textTertiary : CalendarDesign.nearBlack
    }

    private var timeTitle: String {
        guard let startDate = item.startDate else {
            return item.startOrDue.isEmpty ? "-" : item.startOrDue
        }
        if item.isAllDay {
            return "종일"
        }
        if spansMultipleDays {
            return "기간"
        }
        return CalendarFormatting.timeOnly.string(from: startDate)
    }

    private var timeSubtitle: String {
        guard let startDate = item.startDate else { return "" }
        if spansMultipleDays {
            let end = item.displayEndDay ?? item.endDate ?? startDate
            return "\(CalendarFormatting.monthDay.string(from: startDate)) - \(CalendarFormatting.monthDay.string(from: end))"
        }
        if let endDate = item.endDate, !item.isAllDay {
            return "\(CalendarFormatting.timeOnly.string(from: endDate))까지"
        }
        return ""
    }

    private var metaText: String {
        let calendarName = CalendarText.cleanName(item.sourceCalendar)
        if item.hasLocation {
            return "\(CalendarText.cleanName(item.location)) · \(calendarName)"
        }
        return calendarName
    }

    private var spansMultipleDays: Bool {
        guard let startDay = item.displayStartDay, let endDay = item.displayEndDay else {
            return false
        }
        return !Calendar.current.isDate(startDay, inSameDayAs: endDay)
    }
}

struct SelectedItemSheet: View {
    let item: CalendarItem
    let onClose: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let modalWidth = min(560, max(320, proxy.size.width - 28))
            let modalHeight = min(620, max(340, proxy.size.height - 40))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(CalendarPalette.eventTint(for: item))
                            .frame(width: 12, height: 12)
                            .padding(.top, 10)

                        VStack(alignment: .leading, spacing: 7) {
                            Text(CalendarText.cleanName(item.summary))
                                .font(CalendarDesign.displayFont(size: 28, weight: .semibold))
                                .tracking(-0.28)
                                .foregroundStyle(CalendarDesign.nearBlack)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                Text(itemKindText)
                                    .font(CalendarDesign.textFont(size: 12, weight: .semibold))
                                    .tracking(-0.12)
                                    .foregroundStyle(CalendarDesign.textTertiary)

                                Text(statusText)
                                    .font(CalendarDesign.textFont(size: 12, weight: .semibold))
                                    .tracking(-0.12)
                                    .foregroundStyle(CalendarDesign.linkBlue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(CalendarDesign.appleBlue.opacity(0.10))
                                    )
                            }
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        detailRow(label: "시간", value: CalendarFormatting.detailedEventRangeText(for: item))

                        if item.hasLocation {
                            Divider()
                                .overlay(CalendarDesign.divider)
                            detailRow(label: "장소", value: CalendarText.cleanName(item.location))
                        }

                        Divider()
                            .overlay(CalendarDesign.divider)

                        detailRow(label: "캘린더", value: CalendarText.cleanName(item.sourceCalendar))
                    }
                    .calendarModalSectionSurface()

                    if item.hasNote {
                        noteSection
                    }
                }
                .padding(22)
            }
            .frame(width: modalWidth, height: modalHeight)
            .calendarModalContainer()
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("메모")
                .font(CalendarDesign.textFont(size: 13, weight: .semibold))
                .tracking(-0.224)
                .foregroundStyle(CalendarDesign.textTertiary)

            Text(cleanNote)
                .font(CalendarDesign.textFont(size: 15, weight: .regular))
                .tracking(-0.224)
                .foregroundStyle(CalendarDesign.nearBlack)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let url = firstURL {
                Link("예약 정보 열기", destination: url)
                    .font(CalendarDesign.textFont(size: 14, weight: .semibold))
                    .tracking(-0.224)
                    .foregroundStyle(CalendarDesign.linkBlue)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calendarModalSectionSurface()
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(CalendarDesign.textFont(size: 13, weight: .semibold))
                .tracking(-0.224)
                .foregroundStyle(CalendarDesign.textTertiary)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(CalendarDesign.textFont(size: 15, weight: .medium))
                .tracking(-0.224)
                .foregroundStyle(CalendarDesign.nearBlack)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var itemKindText: String {
        item.type == .todo ? "할 일" : "일정"
    }

    private var statusText: String {
        let normalized = item.derivedStatus.uppercased()
        if item.isCompleted { return "완료" }
        if normalized == "CANCELLED" { return "취소됨" }
        if normalized == "TENTATIVE" { return "미정" }
        if normalized == "CONFIRMED" { return "확정" }
        return item.type == .todo ? "진행 중" : "예정"
    }

    private var cleanNote: String {
        CalendarText.cleanName(item.note)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var firstURL: URL? {
        cleanNote
            .components(separatedBy: .whitespacesAndNewlines)
            .lazy
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " <>[](){}\"'")) }
            .first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
            .flatMap(URL.init(string:))
    }
}
