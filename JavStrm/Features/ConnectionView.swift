import SwiftUI

struct ConnectionView: View {
    @Environment(AppSession.self) private var session
    @State private var password = ""
    @FocusState private var focused: Field?
    private enum Field { case server, username, password }

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Palette.accent)
                        Text("JavStrm")
                            .font(.system(size: 46, weight: .bold, design: .serif))
                        Text("你的媒体，随时有序。")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 50)

                    VStack(alignment: .leading, spacing: 20) {
                        Text(session.phase == .login ? "登录服务器" : "连接你的服务器")
                            .font(.title2.weight(.semibold))
                        if session.phase == .login {
                            Label(session.serverInput, systemImage: "server.rack")
                                .font(.caption).foregroundStyle(.secondary)
                            field("用户名") {
                                TextField("admin", text: $session.username)
                                    .textContentType(.username)
                                    .focused($focused, equals: .username)
                                    .submitLabel(.next)
                                    .onSubmit { focused = .password }
                            }
                            field("密码") {
                                SecureField("服务端登录密码", text: $password)
                                    .textContentType(.password)
                                    .focused($focused, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit { submit() }
                            }
                        } else {
                            field("JavStrm 服务地址") {
                                TextField("http://服务器IP:端口", text: $session.serverInput)
                                    .keyboardType(.URL)
                                    .textContentType(.URL)
                                    .focused($focused, equals: .server)
                                    .submitLabel(.go)
                                    .onSubmit { submit() }
                            }
                            Text("请输入已部署的 JavStrm Web 服务地址。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let error = session.connectionError {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(action: submit) {
                            HStack {
                                Spacer()
                                if session.isConnecting { ProgressView().tint(.white) }
                                Text(session.phase == .login ? "登录 JavStrm" : "连接服务器")
                                    .fontWeight(.semibold)
                                Image(systemName: "arrow.right")
                                Spacer()
                            }
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isConnecting || (session.phase == .login && password.isEmpty)
                                  || session.serverInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if session.phase == .login {
                            Button("更换服务器地址") { Task { await session.changeServer() } }
                                .disabled(session.isConnecting)
                        }
                    }
                    .padding(24)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))

                    Label("会话保存在本机钥匙串，密码不会保存。", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("首次连接局域网服务时，请允许本地网络访问。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 520)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background {
                ZStack {
                    Palette.canvas
                    Circle().fill(Palette.accent.opacity(0.07))
                        .frame(width: 360, height: 360).blur(radius: 60)
                        .offset(x: 160, y: -280)
                }
                .ignoresSafeArea()
            }
            .scrollDismissesKeyboard(.interactively)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: session.phase) { _, phase in
                if phase != .login { password = "" }
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content().padding(14).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func submit() {
        focused = nil
        guard !session.isConnecting else { return }
        Task {
            if session.phase == .login { await session.login(password: password) }
            else { await session.connect() }
        }
    }
}
