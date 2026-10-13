import SwiftUI
import JavStrmCore

enum Palette {
    static let accent = Color(red: 0.08, green: 0.43, blue: 0.39)
    static let ink = Color(red: 0.09, green: 0.17, blue: 0.22)
    static let gold = Color(red: 0.77, green: 0.52, blue: 0.22)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct BrandHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(3)
                .foregroundStyle(Palette.accent)
            Text(title)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

struct ErrorPanel: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("暂时无法加载", systemImage: "wifi.exclamationmark").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            if let retry { Button("重试", action: retry).buttonStyle(.bordered) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StatusPill: View {
    let value: String

    private var label: String {
        switch value {
        case "running": "进行中"
        case "queued": "排队中"
        case "done": "已完成"
        case "success": "成功"
        case "skipped": "已跳过"
        case "subtitle_missing": "字幕缺失"
        case "failed": "失败"
        case "waiting": "等待资源"
        case "added": "已提交"
        case "active": "追踪中"
        case "paused": "已暂停"
        case "stale": "待检查"
        case "error": "异常"
        case "canceled": "已取消"
        case "interrupted": "已中断"
        case "in_library": "已入库"
        case "saving", "downloading": "下载中"
        case "processing": "处理中"
        case "downloaded": "下载完成"
        default: value
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(["failed", "error", "interrupted"].contains(value) ? Color.red : Palette.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Palette.accent.opacity(0.08), in: Capsule())
    }
}

enum ArtworkLayout {
    case portrait
    case landscape

    var aspectRatio: CGFloat {
        switch self {
        case .portrait: 2 / 3
        case .landscape: 3 / 2
        }
    }

    var contentMode: ContentMode {
        self == .portrait ? .fill : .fit
    }
}

struct PosterView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("hideArtwork") private var hideArtwork = true
    let source: String
    let code: String
    let layout: ArtworkLayout
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Palette.ink, Palette.accent.opacity(0.8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image, !hideArtwork {
                    if layout == .landscape {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 20)
                            .brightness(-0.25)
                    }
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: layout.contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: hideArtwork ? "eye.slash" : "film")
                            .font(.system(size: 30, weight: .ultraLight))
                        Text(code.isEmpty ? "JAVSTRM" : code)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .tracking(1)
                            .multilineTextAlignment(.center)
                        if failed && !hideArtwork {
                            Text("封面暂不可用").font(.caption2).opacity(0.7)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(12)
                }
            }
        }
        .aspectRatio(layout.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(hideArtwork ? "封面已隐藏，\(code)" : "\(code) 封面")
        .task(id: "\(session.connectionID)|\(source)|\(hideArtwork)") {
            image = nil
            failed = false
            guard !hideArtwork, !source.isEmpty, let client = session.client else { return }
            let connection = session.connectionID
            do {
                let data = try await client.imageData(source)
                guard !Task.isCancelled, connection == session.connectionID, !hideArtwork else { return }
                image = UIImage(data: data)
                failed = image == nil
            } catch {
                guard !Task.isCancelled, connection == session.connectionID else { return }
                failed = true
                session.handle(error)
            }
        }
    }
}

struct MovieCard: View {
    let code: String
    let title: String
    let artwork: String
    let rating: Double
    let artworkLayout: ArtworkLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterView(source: artwork, code: code, layout: artworkLayout)
                .overlay(alignment: .bottomTrailing) {
                    if rating > 0 {
                        Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(8)
                    }
                }
            MovieCardCaption(code: code, title: title)
        }
    }
}

struct MovieCardCaption: View {
    let code: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(code).font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(.primary)
            Text(title.isEmpty ? "等待元数据" : title).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 34, alignment: .top)
        }
    }
}

struct MetricView: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(.title2, design: .rounded).weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct LoadMoreButton: View {
    let isLoading: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading { ProgressView() }
                else { Label("加载更多", systemImage: "arrow.down") }
                Spacer()
            }
            .padding(10)
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)
    }
}

func byteSize(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}
