import SwiftUI
import AppKit
import Network

struct ContentView: View {
    @StateObject private var store = CalendarStore()
    @State private var showingSidebar = false
    @State private var showingSearchSheet = false
    @State private var showingMonthJumpPopover = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                CalendarDesign.lightGray
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topUnifiedHeader
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .calendarNavigationGlass(cornerRadius: 12)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    MonthGridView(store: store)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
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
        HStack(alignment: .center, spacing: 14) {
            Button {
                toggleSidebar()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .calendarAnimatedIcon(rotation: 90, scale: 1.06)
                    .frame(width: 44 * scale, height: 44 * scale)
                    .contentShape(Rectangle())
            }
            .calendarHeaderButtonStyle()

            VStack(alignment: .leading, spacing: 0) {
                Text(CalendarFormatting.dayHeader.string(from: store.selectedDate))
                    .font(CalendarDesign.textFont(size: 14 * scale, weight: .regular))
                    .tracking(-0.224)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(CalendarFormatting.compactMonthTitle.string(from: store.displayedMonth))
                        .font(CalendarDesign.displayFont(size: 46 * scale, weight: .semibold))
                        .tracking(-0.28)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: store.displayedMonth)

                    Button {
                        showingMonthJumpPopover = true
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                            .rotationEffect(.degrees(showingMonthJumpPopover ? 180 : 0))
                            .animation(.snappy(duration: 0.24, extraBounce: 0.04), value: showingMonthJumpPopover)
                            .calendarAnimatedIcon(yOffset: 1)
                            .frame(width: 24 * scale, height: 24 * scale)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.10))
                            )
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
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    showingSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .calendarAnimatedIcon(rotation: -10, scale: 1.08)
                        .frame(width: 44 * scale, height: 44 * scale)
                        .contentShape(Rectangle())
                }
                .calendarHeaderButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 72)
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

private struct SettingsSheet: View {
    @ObservedObject var store: CalendarStore
    let onClose: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var serverURL = "https://caldav.calendar.naver.com"
    @State private var mode: SettingsMode = .list
    @State private var showingDeleteConfirmation = false
    @State private var selectedConnectionID: String?
    @State private var googleOAuthInProgress = false
    @State private var googleOAuthError: String?
    @State private var addMethod: AddMethod?

    var body: some View {
        GeometryReader { proxy in
            let modalWidth = min(540, max(320, proxy.size.width - 28))
            let modalHeight = min(560, max(340, proxy.size.height - 40))

            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsHeader

                        connectedAccountsSection
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)

                if mode != .list {
                    accountEditorOverlay
                        .transition(.scale(scale: 0.985).combined(with: .opacity))
                }

                if showingDeleteConfirmation {
                    deleteConfirmationOverlay
                        .transition(.scale(scale: 0.985).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.18), value: showingDeleteConfirmation)
            .frame(width: modalWidth, height: modalHeight)
            .calendarModalContainer()
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .onAppear {
                resetFormFromStore()
            }
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("연결 설정")
                    .font(CalendarDesign.displayFont(size: 32, weight: .semibold))
                    .tracking(-0.28)
                    .foregroundStyle(CalendarDesign.nearBlack)

                Text("연결된 CalDAV 계정을 관리합니다.")
                    .font(CalendarDesign.textFont(size: 14, weight: .regular))
                    .tracking(-0.224)
                    .foregroundStyle(CalendarDesign.textSecondary)
            }

            Spacer()

            animatedIconButton(
                systemName: "plus",
                help: "계정 추가",
                rotation: 90
            ) {
                prepareAddForm()
            }
        }
    }

    private var connectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("연결된 캘린더")
                .font(CalendarDesign.textFont(size: 13, weight: .semibold))
                .tracking(-0.224)
                .foregroundStyle(CalendarDesign.textTertiary)

            if store.hasSavedConnection {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.connections) { connection in
                        connectedAccountRow(connection)
                    }
                }
            } else {
                emptyConnectionRow
            }
        }
        .padding(14)
        .calendarModalSectionSurface()
    }

    private func connectedAccountRow(_ connection: CalendarConnection) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.displayEmail)
                    .font(CalendarDesign.textFont(size: 16, weight: .semibold))
                    .tracking(-0.224)
                    .foregroundStyle(CalendarDesign.nearBlack)
                    .lineLimit(1)

                Text(connectionStatusText(connection))
                    .font(CalendarDesign.textFont(size: 12, weight: .medium))
                    .tracking(-0.12)
                    .foregroundStyle(store.connectionErrors[connection.id] == nil ? CalendarDesign.textSecondary : Color.red.opacity(0.86))
                    .lineLimit(1)
            }

            Spacer()

            animatedIconButton(
                systemName: "pencil",
                help: "수정",
                rotation: -12
            ) {
                prepareEditForm(connection)
            }

            animatedIconButton(
                systemName: "trash",
                help: "삭제",
                rotation: 8,
                foreground: .white,
                background: Color.red.opacity(0.88)
            ) {
                selectedConnectionID = connection.id
                showingDeleteConfirmation = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CalendarDesign.subtleRowFill)
        )
    }

    private var emptyConnectionRow: some View {
        HStack(spacing: 12) {
            Text("연결된 캘린더가 없습니다.")
                .font(CalendarDesign.textFont(size: 14, weight: .medium))
                .tracking(-0.224)
                .foregroundStyle(CalendarDesign.textSecondary)

            Spacer()

            Button("추가") {
                prepareAddForm()
            }
            .buttonStyle(.plain)
            .font(CalendarDesign.textFont(size: 13, weight: .semibold))
            .foregroundStyle(CalendarDesign.linkBlue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CalendarDesign.subtleRowFill)
        )
    }

    private func formField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(CalendarDesign.textFont(size: 12, weight: .semibold))
                .tracking(-0.12)
                .foregroundStyle(CalendarDesign.textTertiary)
            content()
        }
    }

    private func animatedIconButton(
        systemName: String,
        help: String,
        rotation: Double,
        foreground: Color = CalendarDesign.nearBlack,
        background: Color = CalendarDesign.subtleRowFill,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foreground)
                .calendarAnimatedIcon(rotation: rotation, scale: 1.12)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(background)
                )
                .contentShape(Circle())
        }
        .buttonStyle(CalendarAnimatedIconButtonStyle())
        .help(help)
    }

    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    showingDeleteConfirmation = false
                }

            VStack(alignment: .leading, spacing: 14) {
                Text("연결을 삭제하시겠습니까?")
                    .font(CalendarDesign.textFont(size: 18, weight: .semibold))
                    .tracking(-0.224)
                    .foregroundStyle(CalendarDesign.nearBlack)

                Text("\(selectedConnection?.displayEmail ?? "선택한 계정")의 연결 정보와 현재 불러온 일정이 제거됩니다.")
                    .font(CalendarDesign.textFont(size: 13, weight: .medium))
                    .tracking(-0.12)
                    .foregroundStyle(CalendarDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("취소") {
                        showingDeleteConfirmation = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CalendarDesign.textSecondary)

                    Spacer()

                    Button("삭제") {
                        if let selectedConnectionID {
                            store.deleteConnection(id: selectedConnectionID)
                        }
                        mode = .list
                        resetFormFromStore()
                        selectedConnectionID = nil
                        showingDeleteConfirmation = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.red)
                }
            }
            .padding(18)
            .frame(maxWidth: 360)
            .calendarGlassSurface(cornerRadius: 14, material: .regularMaterial, tintOpacity: 0.24, shadowOpacity: 0.16)
        }
    }

    private var accountEditorOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeAccountEditor()
                }

            VStack(alignment: .leading, spacing: 14) {
                Text(mode == .add ? "계정 추가" : "계정 수정")
                    .font(CalendarDesign.textFont(size: 20, weight: .semibold))
                    .tracking(-0.224)
                    .foregroundStyle(CalendarDesign.nearBlack)

                if let googleOAuthError {
                    Text(googleOAuthError)
                        .font(CalendarDesign.textFont(size: 12, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if mode == .add, addMethod == nil {
                    addMethodChooser
                } else {
                    manualConnectionForm
                }
            }
            .padding(18)
            .frame(maxWidth: 420)
            .calendarGlassSurface(cornerRadius: 14, material: .regularMaterial, tintOpacity: 0.24, shadowOpacity: 0.16)
        }
    }

    private var addMethodChooser: some View {
        VStack(spacing: 10) {
            addMethodButton(
                title: googleOAuthInProgress ? "Google 연결 중..." : "Google Calendar로 연결",
                subtitle: "브라우저에서 Google OAuth로 로그인합니다.",
                systemName: "globe",
                tint: CalendarDesign.appleBlue
            ) {
                connectGoogle()
            }
            .disabled(googleOAuthInProgress)

            addMethodButton(
                title: "이메일 서버로 연결",
                subtitle: "이메일 주소, 암호, CalDAV 서버 주소를 직접 입력합니다.",
                systemName: "server.rack",
                tint: CalendarDesign.nearBlack
            ) {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
                    addMethod = .emailServer
                }
            }

            HStack {
                Button("취소") {
                    closeAccountEditor()
                }
                .buttonStyle(.plain)
                .foregroundStyle(CalendarDesign.textSecondary)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func addMethodButton(
        title: String,
        subtitle: String,
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .calendarAnimatedIcon(rotation: 16, scale: 1.08)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(CalendarDesign.textFont(size: 14, weight: .semibold))
                        .foregroundStyle(CalendarDesign.nearBlack)
                    Text(subtitle)
                        .font(CalendarDesign.textFont(size: 12, weight: .medium))
                        .foregroundStyle(CalendarDesign.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CalendarDesign.subtleRowFill)
            )
        }
        .buttonStyle(CalendarAnimatedIconButtonStyle())
    }

    private var manualConnectionForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            formField(title: "이메일 주소") {
                TextField("name@example.com", text: $email)
                    .textFieldStyle(.plain)
                    .calendarInputSurface()
            }

            formField(title: "암호") {
                SecureField("암호", text: $password)
                    .textFieldStyle(.plain)
                    .calendarInputSurface()
            }

            formField(title: "서버 주소") {
                TextField("https://caldav.calendar.naver.com", text: $serverURL)
                    .textFieldStyle(.plain)
                    .calendarInputSurface()
            }

            HStack {
                Button(mode == .add ? "이전" : "취소") {
                    if mode == .add {
                        withAnimation(.snappy(duration: 0.20, extraBounce: 0.03)) {
                            addMethod = nil
                        }
                    } else {
                        closeAccountEditor()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(CalendarDesign.textSecondary)

                Spacer()

                Button("저장 후 동기화") {
                    let connection = CalendarConnection(
                        id: mode == .edit ? (selectedConnectionID ?? UUID().uuidString) : UUID().uuidString,
                        provider: "caldav",
                        email: email,
                        password: password,
                        serverURL: serverURL
                    )
                    store.upsertConnection(connection)
                    closeAccountEditor()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.calendarAppleBlue)
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
    }

    private func prepareAddForm() {
        selectedConnectionID = nil
        email = ""
        password = ""
        serverURL = "https://caldav.calendar.naver.com"
        googleOAuthError = nil
        addMethod = nil
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
            mode = .add
        }
    }

    private func prepareEditForm(_ connection: CalendarConnection) {
        selectedConnectionID = connection.id
        email = connection.email
        password = connection.password
        serverURL = connection.serverURL
        googleOAuthError = nil
        addMethod = .emailServer
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
            mode = .edit
        }
    }

    private func resetFormFromStore() {
        if let connection = selectedConnection {
            email = connection.email
            password = connection.password
            serverURL = connection.serverURL
        } else {
            email = ""
            password = ""
            serverURL = "https://caldav.calendar.naver.com"
        }
    }

    private func connectGoogle() {
        googleOAuthError = nil
        googleOAuthInProgress = true

        Task {
            do {
                let result = try await GoogleOAuthCoordinator.authorize()
                await MainActor.run {
                    store.upsertConnection(
                        CalendarConnection(
                            id: UUID().uuidString,
                            provider: "google",
                            email: result.email,
                            password: result.refreshToken,
                            serverURL: "https://www.googleapis.com/calendar/v3"
                        )
                    )
                    googleOAuthInProgress = false
                    mode = .list
                }
            } catch {
                await MainActor.run {
                    googleOAuthInProgress = false
                    googleOAuthError = error.localizedDescription
                }
            }
        }
    }

    private func closeAccountEditor() {
        withAnimation(.snappy(duration: 0.20, extraBounce: 0.03)) {
            mode = .list
            selectedConnectionID = nil
            addMethod = nil
            resetFormFromStore()
        }
    }

    private var selectedConnection: CalendarConnection? {
        guard let selectedConnectionID else { return nil }
        return store.connections.first { $0.id == selectedConnectionID }
    }

    private func calendarCount(for connection: CalendarConnection) -> Int {
        store.calendarSourceGroups.first { $0.source == connection.displayServer }?.calendars.count ??
            store.connectionCalendarCounts[connection.id] ?? 0
    }

    private func connectionStatusText(_ connection: CalendarConnection) -> String {
        if connection.serverURL.lowercased().contains("googleusercontent.com"),
           store.connectionErrors[connection.id] != nil {
            return "\(connection.displayServer) · Google CalDAV는 OAuth 연결이 필요합니다"
        }
        if let error = store.connectionErrors[connection.id] {
            return "\(connection.displayServer) · 동기화 실패: \(error)"
        }
        return "\(connection.displayServer) · \(calendarCount(for: connection))개 캘린더"
    }

    private enum SettingsMode {
        case list
        case add
        case edit
    }

    private enum AddMethod {
        case emailServer
    }
}

private struct CalendarColorPalettePopover: View {
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
                                    .stroke(isSelected(option.color) ? CalendarDesign.nearBlack : Color.white.opacity(0.84), lineWidth: isSelected(option.color) ? 2 : 1)
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

private struct MonthJumpPopover: View {
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

                Button("오늘") {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
                        onSelect(Date())
                    }
                }
                .buttonStyle(.plain)
                .font(CalendarDesign.textFont(size: 12, weight: .semibold))
                .tracking(-0.12)
                .foregroundStyle(CalendarDesign.linkBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(CalendarDesign.appleBlue.opacity(0.10))
                )

                yearButton(systemName: "chevron.left") {
                    moveYear(by: -1)
                }

                yearButton(systemName: "chevron.right") {
                    moveYear(by: 1)
                }
            }

            LazyVGrid(columns: monthColumns, spacing: 6) {
                ForEach(1...12, id: \.self) { month in
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

private struct DayAgendaSheet: View {
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

private struct SelectedItemSheet: View {
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

private struct ScheduleSearchSheet: View {
    @ObservedObject var store: CalendarStore
    let onClose: () -> Void
    let onSelect: (CalendarItem) -> Void

    @State private var query = ""
    @State private var rangeStart: Date? = Calendar.current.startOfDay(for: Date())
    @State private var rangeEnd: Date? = Calendar.current.startOfDay(for: Date())
    @State private var showingStartPicker = false
    @State private var showingEndPicker = false

    private var filteredResults: [CalendarItem] {
        let base = store.items.filter { item in
            matchesDateRange(item)
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return base
                .sorted {
                    let left = $0.startDate ?? .distantFuture
                    let right = $1.startDate ?? .distantFuture
                    if left == right {
                        return CalendarText.cleanName($0.summary) < CalendarText.cleanName($1.summary)
                    }
                    return left < right
                }
                .prefix(100)
                .map { $0 }
        }

        return base
            .compactMap { item -> (item: CalendarItem, score: Int)? in
                guard let score = fuzzyScore(query: trimmed, target: CalendarText.cleanName(item.summary)) else {
                    return nil
                }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    let left = lhs.item.startDate ?? .distantFuture
                    let right = rhs.item.startDate ?? .distantFuture
                    if left == right {
                        return CalendarText.cleanName(lhs.item.summary) < CalendarText.cleanName(rhs.item.summary)
                    }
                    return left < right
                }
                return lhs.score < rhs.score
            }
            .prefix(100)
            .map { $0.item }
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
            HStack(alignment: .firstTextBaseline) {
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

                Spacer()

                Button {
                    let today = Calendar.current.startOfDay(for: Date())
                    rangeStart = today
                    rangeEnd = today
                } label: {
                    Text("오늘")
                        .font(CalendarDesign.textFont(size: 12, weight: .semibold))
                        .tracking(-0.12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(CalendarDesign.linkBlue)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(CalendarDesign.appleBlue.opacity(0.10))
                )
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
        let today = Calendar.current.startOfDay(for: Date())
        return (today, today)
    }

    private func thisWeekRange() -> (Date, Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let end = calendar.date(byAdding: DateComponents(day: 6), to: start) ?? today
        return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
    }

    private func thisMonthRange() -> (Date, Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? today
        let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? today
        return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
    }

    private var effectiveRangeStart: Date {
        rangeStart ?? Calendar.current.startOfDay(for: Date())
    }

    private var effectiveRangeEnd: Date {
        rangeEnd ?? effectiveRangeStart
    }

    private var normalizedRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let rawStart = calendar.startOfDay(for: effectiveRangeStart)
        let rawEnd = calendar.startOfDay(for: effectiveRangeEnd)
        return rawStart <= rawEnd ? (rawStart, rawEnd) : (rawEnd, rawStart)
    }

    private var rangeSummary: String {
        let range = normalizedRange
        if Calendar.current.isDate(range.start, inSameDayAs: range.end) {
            return "\(CalendarFormatting.filterDate.string(from: range.start)) 하루"
        }
        return "\(CalendarFormatting.filterDate.string(from: range.start)) - \(CalendarFormatting.filterDate.string(from: range.end))"
    }

    private func matchesDateRange(_ item: CalendarItem) -> Bool {
        let (start, end) = normalizedRange

        guard let itemStart = item.displayStartDay else { return false }
        let itemEnd = item.displayEndDay ?? itemStart

        return itemStart <= end && itemEnd >= start
    }

    private func fuzzyScore(query: String, target: String) -> Int? {
        let q = normalize(query)
        let t = normalize(target)

        guard !q.isEmpty, !t.isEmpty else { return nil }

        if t == q { return 0 }
        if t.hasPrefix(q) { return 1 }
        if t.contains(q) { return 2 }
        if q.contains(t) { return 3 }
        if isSubsequence(q, in: t) { return 4 }

        let distance = levenshteinDistance(q, t)
        let threshold = max(1, q.count / 2 + (q.count >= 6 ? 1 : 0))
        guard distance <= threshold else { return nil }
        return 10 + distance
    }

    private func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func isSubsequence(_ query: String, in target: String) -> Bool {
        var targetIndex = target.startIndex
        for character in query {
            guard let found = target[targetIndex...].firstIndex(of: character) else {
                return false
            }
            targetIndex = target.index(after: found)
        }
        return true
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var current = Array(repeating: 0, count: b.count + 1)
            current[0] = i + 1

            for (j, cb) in b.enumerated() {
                let cost = ca == cb ? 0 : 1
                current[j + 1] = min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + cost
                )
            }
            previous = current
        }
        return previous[b.count]
    }
}

private struct CompactDatePickerPopover: View {
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
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstCell) }
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

private extension View {
    func calendarModalContainer() -> some View {
        self
            .calendarGlassSurface(cornerRadius: 16, material: .regularMaterial, tintOpacity: 0.28, shadowOpacity: 0.18)
    }

    func calendarModalSectionSurface() -> some View {
        self
            .calendarGlassSurface(cornerRadius: 12, material: .thinMaterial, tintOpacity: 0.18, shadowOpacity: 0.035)
    }

    func calendarInputSurface() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .calendarGlassSurface(cornerRadius: 10, material: .ultraThinMaterial, tintOpacity: 0.26, shadowOpacity: 0.02)
    }

    @ViewBuilder
    func calendarHeaderButtonStyle() -> some View {
        self
            .buttonStyle(CalendarAnimatedIconButtonStyle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .calendarGlassSurface(cornerRadius: 10, material: .ultraThinMaterial, tintOpacity: 0.06, shadowOpacity: 0.04)
            .calendarHoverLift(scale: 1.04)
    }

    func calendarNavigationGlass(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.58))
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 26, x: 0, y: 12)
    }
}

private extension Color {
    static let calendarAppleBlue = CalendarDesign.appleBlue
}

struct GoogleOAuthResult {
    let email: String
    let refreshToken: String
}

enum GoogleOAuthCoordinator {
    static func authorize() async throws -> GoogleOAuthResult {
        guard !GoogleOAuthConfig.clientID.isEmpty, !GoogleOAuthConfig.clientSecret.isEmpty else {
            throw CalDAVError.auth("Google OAuth 설정이 없습니다. ~/.lendar/google-oauth.json 또는 LENDAR_GOOGLE_CLIENT_ID/SECRET을 설정하세요.")
        }

        // Desktop OAuth uses a short-lived loopback HTTP server. The browser returns
        // to 127.0.0.1:<port>/oauth2redirect with a one-time authorization code, which
        // is then exchanged for access/refresh tokens.
        let loopback = try await OAuthLoopbackServer.start()
        let state = UUID().uuidString
        let scope = [
            GoogleOAuthConfig.calendarReadOnlyScope,
            "https://www.googleapis.com/auth/userinfo.email",
            "openid"
        ].joined(separator: " ")

        var components = URLComponents(string: GoogleOAuthConfig.authURI)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: loopback.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            throw CalDAVError.auth("Google OAuth URL 생성 실패")
        }

        await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        let callback = try await loopback.waitForCallback()
        guard callback.state == state else {
            throw CalDAVError.auth("Google OAuth state mismatch")
        }

        let token = try await exchangeCode(callback.code, redirectURI: loopback.redirectURI)
        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty,
              let accessToken = token.accessToken, !accessToken.isEmpty else {
            throw CalDAVError.auth("Google refresh token을 받지 못했습니다. 다시 연결해 주세요.")
        }

        let email = try await fetchEmail(accessToken: accessToken)
        return GoogleOAuthResult(email: email, refreshToken: refreshToken)
    }

    private static func exchangeCode(_ code: String, redirectURI: String) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: GoogleOAuthConfig.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "code": code,
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    private static func fetchEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        return try JSONDecoder().decode(GoogleUserInfo.self, from: data).email
    }

    private static func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CalDAVError.network("invalid HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CalDAVError.http(http.statusCode, body)
        }
    }

    private static func formBody(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                "\(urlForm(key))=\(urlForm(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func urlForm(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private struct GoogleUserInfo: Decodable {
    let email: String
}

private final class OAuthLoopbackServer: @unchecked Sendable {
    struct Callback {
        let code: String
        let state: String
    }

    let redirectURI: String
    private let listener: NWListener
    private var continuation: CheckedContinuation<Callback, Error>?

    private init(listener: NWListener, redirectURI: String) {
        self.listener = listener
        self.redirectURI = redirectURI
    }

    static func start() async throws -> OAuthLoopbackServer {
        // Do not use port 0 in redirect_uri. Google will happily accept the URL but the
        // browser cannot callback to a real app listener. Reserve a deterministic local
        // range and pass the actual bound port to the OAuth URL.
        let (listener, port) = try makeListener()
        let server = OAuthLoopbackServer(listener: listener, redirectURI: "http://127.0.0.1:\(port)/oauth2redirect")
        listener.newConnectionHandler = { [weak server] connection in
            server?.handle(connection)
        }
        listener.start(queue: .main)
        return server
    }

    private static func makeListener() throws -> (NWListener, UInt16) {
        for rawPort in 53682...53692 {
            if let port = NWEndpoint.Port(rawValue: UInt16(rawPort)),
               let listener = try? NWListener(using: .tcp, on: port) {
                return (listener, UInt16(rawPort))
            }
        }
        let listener = try NWListener(using: .tcp, on: .any)
        return (listener, listener.port?.rawValue ?? 53682)
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                self?.finish(connection: connection, result: .failure(CalDAVError.auth("OAuth callback 수신 실패")))
                return
            }

            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let target = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            guard let url = URL(string: "http://127.0.0.1\(target)"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                finish(connection: connection, result: .failure(CalDAVError.auth("OAuth callback URL 파싱 실패")))
                return
            }

            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let error = query["error"], !error.isEmpty {
                finish(connection: connection, result: .failure(CalDAVError.auth(error)))
                return
            }

            guard let code = query["code"], let state = query["state"] else {
                finish(connection: connection, result: .failure(CalDAVError.auth("OAuth code 누락")))
                return
            }

            finish(connection: connection, result: .success(Callback(code: code, state: state)))
        }
    }

    private func finish(connection: NWConnection, result: Result<Callback, Error>) {
        let html = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        \r
        <html><body><h3>lendar Google 연결이 완료되었습니다.</h3><p>이 창은 닫아도 됩니다.</p></body></html>
        """
        connection.send(content: Data(html.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
        listener.cancel()

        switch result {
        case .success(let callback):
            continuation?.resume(returning: callback)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
