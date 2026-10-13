import SwiftUI
import UIKit

// A separate window also covers sheets and WebKit when iOS snapshots the app.
struct PrivacyShield: UIViewRepresentable {
    let enabled: Bool
    let isVisible: Bool

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        uiView.enabled = enabled
        uiView.setVisible(enabled && isVisible)
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: ()) { uiView.removeShield() }

    final class AnchorView: UIView {
        var enabled = true
        private var shield: UIWindow?
        private var wantsShield = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(self, selector: #selector(resignActive),
                                                   name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(becomeActive),
                                                   name: UIApplication.didBecomeActiveNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        deinit { NotificationCenter.default.removeObserver(self) }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { setVisible(wantsShield) }
            else { removeShield() }
        }

        func setVisible(_ visible: Bool) {
            wantsShield = visible
            guard visible, enabled, let scene = window?.windowScene else { removeShield(); return }
            if shield == nil {
                let cover = UIWindow(windowScene: scene)
                cover.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
                cover.rootViewController = UIHostingController(rootView: PrivacyCurtain())
                cover.isUserInteractionEnabled = false
                shield = cover
            }
            shield?.isHidden = false
        }

        func removeShield() {
            shield?.isHidden = true
            shield = nil
        }

        @objc private func resignActive() { if enabled { setVisible(true) } }
        @objc private func becomeActive() { setVisible(false) }
    }
}
