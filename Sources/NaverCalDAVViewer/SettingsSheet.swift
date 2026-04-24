import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var store: CalendarStore
    let onClose: () -> Void

    @State private var form = SettingsFormState()
    @State private var showingDeleteConfirmation = false
    @State private var googleOAuthInProgress = false
    @State private var googleOAuthError: String?

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

                if form.isEditing {
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
                form.reset(from: selectedConnection)
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
                form.selectedConnectionID = connection.id
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

    private func formField(title: String, @ViewBuilder content: () -> some View) -> some View {
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
                        if let selectedConnectionID = form.selectedConnectionID {
                            store.deleteConnection(id: selectedConnectionID)
                        }
                        form.mode = .list
                        form.reset(from: selectedConnection)
                        form.selectedConnectionID = nil
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
                Text(form.mode == .add ? "계정 추가" : "계정 수정")
                    .font(CalendarDesign.textFont(size: 20, weight: .semibold))
                    .tracking(-0.224)
                    .foregroundStyle(CalendarDesign.nearBlack)

                if let googleOAuthError {
                    Text(googleOAuthError)
                        .font(CalendarDesign.textFont(size: 12, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if form.shouldShowAddMethodChooser {
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
                    form.addMethod = .emailServer
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
                TextField("name@example.com", text: $form.email)
                    .textFieldStyle(.plain)
                    .calendarInputSurface()
            }

            formField(title: "암호") {
                SecureField("암호", text: $form.password)
                    .textFieldStyle(.plain)
                    .calendarInputSurface()
            }

            formField(title: "서버 주소") {
                TextField("https://caldav.calendar.naver.com", text: $form.serverURL)
                    .textFieldStyle(.plain)
                    .calendarInputSurface()
            }

            HStack {
                Button(form.mode == .add ? "이전" : "취소") {
                    if form.mode == .add {
                        withAnimation(.snappy(duration: 0.20, extraBounce: 0.03)) {
                            form.addMethod = nil
                        }
                    } else {
                        closeAccountEditor()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(CalendarDesign.textSecondary)

                Spacer()

                Button("저장 후 동기화") {
                    store.upsertConnection(form.manualConnection())
                    closeAccountEditor()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.calendarAppleBlue)
                .disabled(!form.canSaveManualConnection)
            }
            .padding(.top, 4)
        }
    }

    private func prepareAddForm() {
        googleOAuthError = nil
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
            form.prepareAdd()
        }
    }

    private func prepareEditForm(_ connection: CalendarConnection) {
        googleOAuthError = nil
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) {
            form.prepareEdit(connection)
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
                    form.mode = .list
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
            form.closeEditor(selectedConnection: selectedConnection)
        }
    }

    private var selectedConnection: CalendarConnection? {
        guard let selectedConnectionID = form.selectedConnectionID else { return nil }
        return store.connections.first { $0.id == selectedConnectionID }
    }

    private func calendarCount(for connection: CalendarConnection) -> Int {
        store.calendarSourceGroups.first { $0.source == connection.displayServer }?.calendars.count ??
            store.connectionCalendarCounts[connection.id] ?? 0
    }

    private func connectionStatusText(_ connection: CalendarConnection) -> String {
        if connection.serverURL.lowercased().contains("googleusercontent.com"),
           store.connectionErrors[connection.id] != nil
        {
            return "\(connection.displayServer) · Google CalDAV는 OAuth 연결이 필요합니다"
        }
        if let error = store.connectionErrors[connection.id] {
            return "\(connection.displayServer) · 동기화 실패: \(error)"
        }
        return "\(connection.displayServer) · \(calendarCount(for: connection))개 캘린더"
    }
}
