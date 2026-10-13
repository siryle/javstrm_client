import SwiftUI
import JavStrmCore

struct PosterCropView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hideArtwork") private var hideArtwork = true
    let movie: LibraryMovie
    let onSaved: () async -> Void
    @State private var image: UIImage?
    @State private var selection: PosterCropSelection?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var loadID = UUID()
    @GestureState private var moveTranslation = CGSize.zero
    @GestureState private var resizeTranslation = CGSize.zero

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(movie.code)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                Text("拖动选框调整位置，拖动右下角控制点调整大小。封面宽高比固定为 2:3。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if hideArtwork {
                    ContentUnavailableView("封面已隐藏", systemImage: "eye.slash",
                                           description: Text("请先在媒体库显示封面，再进行裁切。"))
                } else if let image, let selection {
                    cropStage(image: image, selection: selection)
                    Button("重置选框") {
                        self.selection = PosterCropSelection(imageWidth: selection.imageWidth,
                                                            imageHeight: selection.imageHeight)
                    }
                    .buttonStyle(.bordered)
                    .disabled(saving)
                } else if loading {
                    ProgressView("正在读取原始封面").frame(maxWidth: .infinity).padding(60)
                }
                if let error {
                    ErrorPanel(message: error, retry: image == nil ? { Task { await load() } } : nil)
                }
            }
            .padding(24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
        .navigationTitle("裁切封面")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView() }
                    else { Text("保存裁切") }
                }
                .disabled(saving || loading || hideArtwork || selection == nil)
            }
        }
        .interactiveDismissDisabled(saving)
        .task(id: "\(session.connectionID)|\(movie.cropArtwork)|\(hideArtwork)") { await load() }
    }

    private func cropStage(image: UIImage, selection: PosterCropSelection) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(CGFloat(selection.imageWidth) / CGFloat(selection.imageHeight), contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let scale = geometry.size.width / CGFloat(selection.imageWidth)
                    let current = displayedSelection(selection, scale: scale)
                    let rect = CGRect(x: CGFloat(current.x) * scale, y: CGFloat(current.y) * scale,
                                      width: CGFloat(current.width) * scale,
                                      height: CGFloat(current.height) * scale)
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: geometry.size))
                            path.addRect(rect)
                        }
                        .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                        Rectangle()
                            .fill(.clear)
                            .overlay { Rectangle().stroke(.white, lineWidth: 2) }
                            .frame(width: rect.width, height: rect.height)
                            .contentShape(Rectangle())
                            .position(x: rect.midX, y: rect.midY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .updating($moveTranslation) { value, state, _ in state = value.translation }
                                    .onEnded { value in
                                        self.selection = selection.moved(
                                            dx: Double(value.translation.width / scale),
                                            dy: Double(value.translation.height / scale))
                                    }
                            )
                            .accessibilityLabel("裁切选框")
                            .accessibilityHint("向上或向下轻扫可左右移动选框")
                            .accessibilityAdjustableAction { direction in
                                let step = Double(selection.imageWidth) * 0.05
                                self.selection = selection.moved(
                                    dx: direction == .increment ? step : -step, dy: 0)
                            }
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 16, height: 16)
                            .overlay { Circle().stroke(.white, lineWidth: 2) }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .position(x: rect.maxX, y: rect.maxY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .updating($resizeTranslation) { value, state, _ in state = value.translation }
                                    .onEnded { value in
                                        self.selection = selection.resized(
                                            widthDelta: Double(value.translation.width / scale),
                                            minimumWidth: Double(48 / scale))
                                    }
                            )
                            .accessibilityLabel("调整裁切大小")
                            .accessibilityAdjustableAction { direction in
                                let step = Double(selection.imageWidth) * 0.05
                                self.selection = selection.resized(
                                    widthDelta: direction == .increment ? step : -step,
                                    minimumWidth: Double(48 / scale))
                            }
                    }
                }
            }
            .padding(22)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(!saving)
    }

    private func displayedSelection(_ selection: PosterCropSelection, scale: CGFloat) -> PosterCropSelection {
        let moved = selection.moved(dx: Double(moveTranslation.width / scale),
                                    dy: Double(moveTranslation.height / scale))
        guard resizeTranslation != .zero else { return moved }
        return moved.resized(widthDelta: Double(resizeTranslation.width / scale),
                             minimumWidth: Double(48 / scale))
    }

    private func load() async {
        let request = UUID()
        loadID = request
        loading = false
        image = nil
        selection = nil
        error = nil
        guard !hideArtwork, let api = session.client else { return }
        guard !movie.cropArtwork.isEmpty else {
            error = "该影片没有可裁切的封面图。"
            return
        }
        let connection = session.connectionID
        loading = true
        defer { if loadID == request { loading = false } }
        do {
            let data = try await api.imageData(movie.cropArtwork)
            guard !Task.isCancelled, loadID == request, connection == session.connectionID, !hideArtwork else { return }
            guard let decoded = UIImage(data: data), let bitmap = decoded.cgImage else {
                throw APIError.invalidResponse
            }
            let swapsAxes: Bool
            switch decoded.imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored: swapsAxes = true
            default: swapsAxes = false
            }
            guard let selection = PosterCropSelection(
                imageWidth: swapsAxes ? bitmap.height : bitmap.width,
                imageHeight: swapsAxes ? bitmap.width : bitmap.height)
            else { throw APIError.invalidResponse }
            image = decoded
            self.selection = selection
        } catch {
            guard !Task.isCancelled, loadID == request, connection == session.connectionID else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }

    private func save() async {
        guard !saving, !hideArtwork, let selection, let api = session.client else { return }
        let connection = session.connectionID
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await api.cropLibraryPoster(movieID: movie.id, crop: selection.crop)
            guard connection == session.connectionID else { return }
            await onSaved()
            guard connection == session.connectionID else { return }
            session.notice = AppSession.Notice(message: "封面已裁切。")
            dismiss()
        } catch {
            guard connection == session.connectionID else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
