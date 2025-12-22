import SwiftUI
import UIKit
import GhosttyKit
import os.log

/// SwiftUI wrapper for the Ghostty terminal surface
/// Based on: ~/Projects/ghostty/macos/Sources/Ghostty/SurfaceView_UIKit.swift
struct TerminalSurface: UIViewRepresentable {
    @ObservedObject var ghosttyApp: GhosttyApp

    func makeUIView(context: Context) -> TerminalSurfaceView {
        guard let app = ghosttyApp.app else {
            Logger.clauntty.error("Cannot create TerminalSurfaceView: GhosttyApp not initialized")
            return TerminalSurfaceView(frame: .zero, app: nil)
        }
        return TerminalSurfaceView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), app: app)
    }

    func updateUIView(_ uiView: TerminalSurfaceView, context: Context) {
        // Update view if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: TerminalSurface

        init(_ parent: TerminalSurface) {
            self.parent = parent
        }
    }
}

/// UIKit view that hosts the Ghostty terminal
/// Uses CAMetalLayer for GPU-accelerated rendering
class TerminalSurfaceView: UIView, ObservableObject, UIKeyInput {

    // MARK: - Published Properties

    @Published var title: String = "Terminal"
    @Published var healthy: Bool = true
    @Published var error: Error? = nil

    // MARK: - Ghostty Surface

    private(set) var surface: ghostty_surface_t?

    // MARK: - Initialization

    init(frame: CGRect, app: ghostty_app_t?) {
        super.init(frame: frame)
        setupView()

        guard let app = app else {
            Logger.clauntty.error("TerminalSurfaceView: No app provided")
            return
        }

        // Create surface configuration for iOS
        var config = ghostty_surface_config_new()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_IOS
        config.platform = ghostty_platform_u(ios: ghostty_platform_ios_s(
            uiview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.scale_factor = UIScreen.main.scale

        // Create the surface
        guard let surface = ghostty_surface_new(app, &config) else {
            Logger.clauntty.error("ghostty_surface_new failed")
            return
        }

        self.surface = surface
        Logger.clauntty.info("Terminal surface created successfully")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    deinit {
        if let surface = self.surface {
            ghostty_surface_free(surface)
        }
    }

    private func setupView() {
        // Configure for Metal rendering
        backgroundColor = .black

        // Enable user interaction for keyboard
        isUserInteractionEnabled = true
    }

    // MARK: - Layer

    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }

    var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }

    /// Called by GhosttyKit's Metal renderer to add sublayers
    /// GhosttyKit calls this on the view, but it's a CALayer method,
    /// so we forward to our layer.
    /// Note: GhosttyKit calls objc.sel("addSublayer") which becomes "addSublayer:" selector
    @objc(addSublayer:)
    func addSublayer(_ sublayer: CALayer) {
        Logger.clauntty.info("addSublayer called on view, forwarding to layer")
        layer.addSublayer(sublayer)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        sizeDidChange(bounds.size)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            sizeDidChange(frame.size)
        }
    }

    func sizeDidChange(_ size: CGSize) {
        guard let surface = self.surface else { return }

        let scale = contentScaleFactor
        ghostty_surface_set_content_scale(surface, scale, scale)
        ghostty_surface_set_size(
            surface,
            UInt32(size.width * scale),
            UInt32(size.height * scale)
        )
    }

    // MARK: - Focus

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            focusDidChange(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            focusDidChange(false)
        }
        return result
    }

    func focusDidChange(_ focused: Bool) {
        guard let surface = self.surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    // MARK: - UIKeyInput

    var hasText: Bool {
        return true
    }

    func insertText(_ text: String) {
        // Send text input to ghostty
        // TODO: Call ghostty_surface_text when GhosttyKit is available
        // text.withCString { cStr in
        //     ghostty_surface_text(surface, cStr, UInt(text.utf8.count))
        // }
        print("Input: \(text)")  // Debug placeholder
    }

    func deleteBackward() {
        // Send backspace to ghostty
        // TODO: Call ghostty_surface_key with backspace key
        print("Backspace")  // Debug placeholder
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Become first responder to show keyboard
        if !isFirstResponder {
            becomeFirstResponder()
        }
    }
}

// MARK: - Preview

#Preview {
    TerminalSurface(ghosttyApp: GhosttyApp())
        .ignoresSafeArea()
}
