import SwiftUI
import JavStrmCore

struct PanLoginView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let onAuthorized: () async -> Void
    @State private var method: PanScanMethod = .alipay
    @State private var requestID = UUID()
    @State private var login: PanLoginSession?
    @State private var image: UIImage?
    @State private var state: PanLoginState = .waiting
    @State private var loading = false
    @State private var error: String?

    private struct PollKey: Equatable {
        let requestID: UUID
        let active: Bool
    }

    var body: some View {
        Form {
            Section {
                Picker("扫码方式", selection: $method) {
                    ForEach(PanScanMethod.allCases, id: \.self) { method in
                        Text(method.title).tag(method)
                    }
                }
                .disabled(state == .authorized)
                VStack(spacing: 16) {
                    if let image, state.isPending {
                        Image(uiImage: image)
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(maxWidth: 256, maxHeight: 256)
                            .padding(12).background(.white)
                            .accessibilityLabel("115 登录二维码")
                    } else if loading {
                        ProgressView("正在获取二维码").frame(height: 256)
                    } else {
                        Image(systemName: state == .authorized ? "checkmark.circle" : "qrcode")
                            .font(.system(size: 72)).foregroundStyle(.secondary)
                            .frame(height: 256)
                    }
                    Text(state.message).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical)
            } footer: {
                Text("使用对应客户端扫描二维码并确认登录。登录凭据保存在服务器。")
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Button("重新获取二维码") { restart() }
                .disabled(loading || state == .authorized)
        }
        .navigationTitle("扫码登录 115")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: method) { restart() }
        .task(id: PollKey(requestID: requestID, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await pollLogin()
        }
    }

    private func restart() {
        login = nil
        image = nil
        state = .waiting
        error = nil
        requestID = UUID()
    }

    private func pollLogin() async {
        guard let api = session.client else { return }
        let connectionID = session.connectionID
        let attempt = requestID
        func isCurrent() -> Bool {
            !Task.isCancelled && attempt == requestID && connectionID == session.connectionID
        }
        if login == nil {
            loading = true
            error = nil
            do {
                let result = try await api.beginPanLogin(method: method)
                guard isCurrent() else { return }
                guard let data = result.qrCodeData, let qrImage = UIImage(data: data) else {
                    throw APIError.invalidResponse
                }
                login = result
                image = qrImage
                state = .waiting
                loading = false
            } catch {
                guard isCurrent() else { return }
                loading = false
                self.error = session.describe(error)
                session.handle(error)
                return
            }
        }
        if state == .authorized {
            await finishLogin(attempt: attempt, connectionID: connectionID)
            return
        }
        guard let login, state.isPending else { return }
        var failures = 0
        while isCurrent() {
            do {
                let next = try await api.panLoginStatus(id: login.id)
                guard isCurrent() else { return }
                state = next
                failures = 0
                error = nil
                if next == .authorized {
                    await finishLogin(attempt: attempt, connectionID: connectionID)
                    return
                }
                if !next.isPending { return }
            } catch {
                guard isCurrent() else { return }
                failures += 1
                self.error = session.describe(error)
                session.handle(error)
                if error as? APIError == .authenticationRequired || failures >= 5 { return }
            }
            do { try await Task.sleep(for: .milliseconds(1500)) }
            catch { return }
        }
    }

    private func finishLogin(attempt: UUID, connectionID: UUID) async {
        await onAuthorized()
        guard !Task.isCancelled, attempt == requestID, connectionID == session.connectionID else { return }
        await session.refreshTasks()
        guard !Task.isCancelled, attempt == requestID, connectionID == session.connectionID else { return }
        dismiss()
    }
}
