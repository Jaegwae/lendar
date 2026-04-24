import SwiftUI

/// Main SwiftUI surface: toolbar, sidebar, modal stack, settings, search,
/// and day agenda. Network/OAuth and pure search/layout logic live in helpers.
struct ContentView: View {
    @StateObject private var store = CalendarStore()
    @State private var showingSidebar = false
    @State private var showingSearchSheet = false
    @State private var showingMonthJumpPopover = false
    @State private var colorPickerCalendarName: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                CalendarDesign.calendarCanvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topUnifiedHeader
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .calendarTopChrome()

                    MonthGridView(store: store)
                        .padding(.horizontal, 0)
                        .padding(.bottom, 0)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Color.black.opacity(showingSidebar ? 0.06 : 0.0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .allowsHitTesting(showingSidebar)
                    .onTapGesture {
                        closeSidebar()
                    }
                    .animation(.smooth(duration: 0.22), value: showingSidebar)
                    .zIndex(10)

                sidebarDrawer
                    .frame(height: proxy.size.height)
                    .offset(x: showingSidebar ? 0 : -336)
                    .animation(.snappy(duration: 0.30, extraBounce: 0.03), value: showingSidebar)
                    .zIndex(20)

                modalLayer
                    .zIndex(30)
            }
        }
        .onAppear {
            store.jumpToToday()
            store.autoLoadIfPossible()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSyncSettings)) { _ in
            showingSidebar = false
            store.showingSettingsSheet = true
        }
    }

    @ViewBuilder
    private var modalLayer: some View {
        if isAnyModalPresented {
            ZStack {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeTopModal()
                    }

                currentModal
                    .transition(.scale(scale: 0.985).combined(with: .opacity))
            }
            .animation(.smooth(duration: 0.18), value: modalPresentationKey)
        }
    }

    @ViewBuilder
    private var currentModal: some View {
        if store.showingDetailSheet, let selectedItem = store.selectedItem {
            SelectedItemSheet(item: selectedItem) {
                store.showingDetailSheet = false
            }
        } else if store.showingDaySheet {
            DayAgendaSheet(
                date: store.selectedDate,
                items: store.items(for: store.selectedDate),
                selectedItem: Binding(
                    get: { store.selectedItem },
                    set: { item in
                        if let item {
                            store.selectItem(item)
                        }
                    }
                ),
                onClose: {
                    store.showingDaySheet = false
                },
                onOpenDetail: { item in
                    store.selectItem(item)
                    store.showingDetailSheet = true
                }
            )
        } else if showingSearchSheet {
            ScheduleSearchSheet(
                store: store,
                onClose: {
                    showingSearchSheet = false
                },
                onSelect: { item in
                    showingSearchSheet = false
                    store.focusItem(item)
                    store.showingDetailSheet = true
                }
            )
        } else if store.showingSettingsSheet {
            SettingsSheet(
                store: store,
                onClose: {
                    store.showingSettingsSheet = false
                }
            )
        }
    }

    private var isAnyModalPresented: Bool {
        store.showingSettingsSheet || showingSearchSheet || store.showingDaySheet || store.showingDetailSheet
    }

    private var modalPresentationKey: String {
        if store.showingDetailSheet { return "detail" }
        if store.showingDaySheet { return "day" }
        if showingSearchSheet { return "search" }
        if store.showingSettingsSheet { return "settings" }
        return "none"
    }

    private func closeTopModal() {
        if store.showingDetailSheet {
            store.showingDetailSheet = false
        } else if store.showingDaySheet {
            store.showingDaySheet = false
        } else if showingSearchSheet {
            showingSearchSheet = false
        } else if store.showingSettingsSheet {
            store.showingSettingsSheet = false
        }
    }

    private var topUnifiedHeader: some View {
        GeometryReader { proxy in
            let scale = min(1.0, max(0.82, proxy.size.width / 760.0))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        toggleSidebar()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 17 * scale, weight: .semibold))
                            .foregroundStyle(CalendarDesign.textSecondary)
                            .calendarAnimatedIcon(rotation: 90, scale: 1.06)
                            .frame(width: 44 * scale, height: 44 * scale)
                            .contentShape(Rectangle())
                    }
                    .calendarHeaderButtonStyle()

                    Spacer()

                    Button {
                        showingSearchSheet = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18 * scale, weight: .semibold))
                            .foregroundStyle(CalendarDesign.nearBlack.opacity(0.82))
                            .calendarAnimatedIcon(rotation: -10, scale: 1.08)
                            .frame(width: 44 * scale, height: 44 * scale)
                            .contentShape(Circle())
                    }
                    .calendarHeaderButtonStyle()
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(CalendarFormatting.monthTitle.string(from: store.displayedMonth))
                        .font(CalendarDesign.displayFont(size: 34 * scale, weight: .semibold))
                        .tracking(-0.28)
                        .foregroundStyle(CalendarDesign.nearBlack)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: store.displayedMonth)

                    Button {
                        showingMonthJumpPopover = true
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11 * scale, weight: .bold))
                            .foregroundStyle(CalendarDesign.textSecondary)
                            .rotationEffect(.degrees(showingMonthJumpPopover ? 180 : 0))
                            .animation(.snappy(duration: 0.24, extraBounce: 0.04), value: showingMonthJumpPopover)
                            .calendarAnimatedIcon(yOffset: 1)
                            .frame(width: 24 * scale, height: 24 * scale)
                            .background(Circle().fill(CalendarDesign.subtleRowFill))
                    }
                    .buttonStyle(CalendarAnimatedIconButtonStyle())
                    .help("연월 바로 이동")
                    .popover(isPresented: $showingMonthJumpPopover, arrowEdge: .top) {
                        MonthJumpPopover(
                            currentMonth: store.displayedMonth,
                            onSelect: { month in
                                store.jumpToMonth(month)
                                showingMonthJumpPopover = false
                            },
                            onClose: {
                                showingMonthJumpPopover = false
                            }
                        )
                    }

                    Spacer()

                    monthStepControls(scale: scale)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 104)
    }

    private func monthStepControls(scale: CGFloat) -> some View {
        HStack(spacing: 8) {
            MonthStepChevronButton(systemName: "chevron.left", direction: .backward, help: "이전 달") {
                store.moveMonth(by: -1)
            }

            Button {
                store.jumpToToday()
            } label: {
                Text("오늘")
                    .font(CalendarDesign.textFont(size: 13 * scale, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(CalendarDesign.nearBlack)
                    .padding(.horizontal, 14 * scale)
                    .frame(height: 30 * scale)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CalendarDesign.subtleRowFill)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(CalendarDesign.glassHairline, lineWidth: 1)
                    )
            }
            .buttonStyle(CalendarAnimatedIconButtonStyle())

            MonthStepChevronButton(systemName: "chevron.right", direction: .forward, help: "다음 달") {
                store.moveMonth(by: 1)
            }
        }
        .padding(.trailing, 4)
    }

    private var sidebarDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(store.calendarSourceGroups, id: \.source) { group in
                        calendarSourceBlock(title: group.source, items: group.calendars)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .calendarGlassSurface(cornerRadius: 14, material: .regularMaterial, tintOpacity: 0.22, shadowOpacity: 0.16)
        .padding(.vertical, 12)
        .padding(.leading, 12)
    }

    private func toggleSidebar() {
        withAnimation(.snappy(duration: 0.30, extraBounce: 0.03)) {
            showingSidebar.toggle()
        }
    }

    private func calendarSourceBlock(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(CalendarDesign.textFont(size: 14, weight: .semibold))
                .tracking(-0.12)
                .foregroundStyle(CalendarDesign.textTertiary)
                .lineLimit(1)
                .padding(.leading, 1)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { name in
                    sidebarCalendarRow(name)
                }
            }
        }
    }

    private func closeSidebar() {
        withAnimation(.smooth(duration: 0.22)) {
            showingSidebar = false
        }
    }

    private func sidebarCalendarRow(_ name: String) -> some View {
        let isVisible = store.visibleCalendars.contains(name)
        let color = CalendarPalette.color(for: name, code: store.colorCode(for: name))

        return HStack(spacing: 14) {
            Button {
                store.toggleCalendar(name)
            } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isVisible ? color : Color.gray.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black.opacity(0.76))
                            .opacity(isVisible ? 1 : 0.70)
                            .calendarAnimatedIcon(scale: 1.14)
                    )
                    .animation(.snappy(duration: 0.18, extraBounce: 0.08), value: isVisible)
            }
            .buttonStyle(.plain)

            Button {
                store.toggleCalendar(name)
            } label: {
                Text(CalendarText.calendarDisplayName(name))
                    .font(CalendarDesign.textFont(size: 16, weight: .medium))
                    .tracking(-0.224)
                    .foregroundStyle(isVisible ? CalendarDesign.nearBlack : CalendarDesign.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                colorPickerCalendarName = name
            } label: {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(CalendarDesign.glassHighlight.opacity(0.80), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.24), radius: 5, x: 0, y: 2)
                    .calendarHoverLift(scale: 1.10)
            }
            .buttonStyle(CalendarAnimatedIconButtonStyle())
            .popover(isPresented: Binding(
                get: { colorPickerCalendarName == name },
                set: { isPresented in
                    colorPickerCalendarName = isPresented ? name : nil
                }
            ), arrowEdge: .trailing) {
                CalendarColorPalettePopover(
                    selectedCode: store.colorCode(for: name),
                    onSelect: { color in
                        store.setCalendarColor(color, for: name)
                        colorPickerCalendarName = nil
                    }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contextMenu {
            ForEach(Array(CalendarPalette.choices.enumerated()), id: \.offset) { _, option in
                Button(option.name) {
                    store.setCalendarColor(option.color, for: name)
                }
            }
        }
    }
}

private enum MonthStepDirection {
    case backward
    case forward

    var rotation: Double {
        switch self {
        case .backward: -18
        case .forward: 18
        }
    }

    var tapOffset: CGFloat {
        switch self {
        case .backward: -3
        case .forward: 3
        }
    }
}

private struct MonthStepChevronButton: View {
    let systemName: String
    let direction: MonthStepDirection
    let help: String
    let action: () -> Void

    @State private var isHovering = false
    @State private var tapPulse = false

    var body: some View {
        Button {
            triggerTapAnimation()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CalendarDesign.textSecondary)
                .scaleEffect(isHovering || tapPulse ? 1.16 : 1)
                .rotationEffect(.degrees(isHovering ? direction.rotation : 0))
                .offset(x: tapPulse ? direction.tapOffset : 0)
                .animation(.snappy(duration: 0.20, extraBounce: 0.08), value: isHovering)
                .animation(.snappy(duration: 0.16, extraBounce: 0.12), value: tapPulse)
                .frame(width: 30, height: 30)
                .background(Circle().fill(CalendarDesign.subtleRowFill))
                .overlay(Circle().stroke(CalendarDesign.glassHairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(CalendarAnimatedIconButtonStyle())
        .help(help)
        .onHover { isHovering = $0 }
    }

    private func triggerTapAnimation() {
        tapPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            tapPulse = false
        }
    }
}
