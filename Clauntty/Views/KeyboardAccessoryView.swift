import UIKit
import os.log
import Combine

enum KeyboardBarActionKind: String, Codable, CaseIterable, Identifiable {
    case empty
    case mic
    case esc
    case tab
    case ctrl
    case fn
    case ctrlC
    case ctrlO
    case ctrlB
    case enter
    case backtick
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case backspace
    case deleteForward
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case snippet
    case customKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .empty: return "Empty"
        case .mic: return "Mic"
        case .esc: return "Esc"
        case .tab: return "Tab"
        case .ctrl: return "Ctrl"
        case .fn: return "Fn"
        case .ctrlC: return "^C"
        case .ctrlO: return "^O"
        case .ctrlB: return "^B"
        case .enter: return "Enter"
        case .backtick: return "Backtick (`)"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .backspace: return "Backspace"
        case .deleteForward: return "Delete Forward"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .snippet: return "Snippet"
        case .customKey: return "Custom Key"
        }
    }

    static let pickerOrder: [KeyboardBarActionKind] = [
        .empty,
        .mic, .esc, .tab, .ctrl, .fn, .ctrlC, .ctrlO, .ctrlB, .enter, .backtick,
        .up, .down, .left, .right, .home, .end, .pageUp, .pageDown, .backspace, .deleteForward,
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
        .snippet, .customKey
    ]
}

struct KeyboardBarAction: Codable, Equatable, Identifiable {
    var kind: KeyboardBarActionKind
    var snippetText: String? = nil
    var snippetLabel: String? = nil
    var snippetRunOnTap: Bool? = nil
    var customText: String? = nil
    var customLabel: String? = nil
    var holdKind: KeyboardBarActionKind? = nil
    var holdSnippetText: String? = nil
    var holdSnippetLabel: String? = nil
    var holdSnippetRunOnTap: Bool? = nil
    var holdCustomText: String? = nil
    var holdCustomLabel: String? = nil

    var id: String {
        "\(kind.rawValue):\(snippetLabel ?? ""):\(snippetText ?? ""):\(snippetRunOnTap ?? false):\(customLabel ?? ""):\(customText ?? ""):\(holdKind?.rawValue ?? ""):\(holdSnippetLabel ?? ""):\(holdSnippetText ?? ""):\(holdSnippetRunOnTap ?? false):\(holdCustomLabel ?? ""):\(holdCustomText ?? "")"
    }

    static func fixed(_ kind: KeyboardBarActionKind) -> KeyboardBarAction {
        KeyboardBarAction(kind: kind)
    }

    var holdAction: KeyboardBarAction? {
        guard let holdKind else { return nil }
        return KeyboardBarAction(
            kind: holdKind,
            snippetText: holdSnippetText,
            snippetLabel: holdSnippetLabel,
            snippetRunOnTap: holdSnippetRunOnTap,
            customText: holdCustomText,
            customLabel: holdCustomLabel
        )
    }

    mutating func setHoldAction(_ action: KeyboardBarAction?) {
        holdKind = action?.kind
        holdSnippetText = action?.snippetText
        holdSnippetLabel = action?.snippetLabel
        holdSnippetRunOnTap = action?.snippetRunOnTap
        holdCustomText = action?.customText
        holdCustomLabel = action?.customLabel
    }
}

struct KeyboardBarLayout: Codable, Equatable {
    static let leftSlotCount = 4
    static let rightSlotCount = 4

    var leftSlots: [KeyboardBarAction]
    var rightSlots: [KeyboardBarAction]

    static let `default` = KeyboardBarLayout(
        leftSlots: [
            .fixed(.mic),
            .fixed(.esc),
            .fixed(.tab),
            .fixed(.ctrl),
        ],
        rightSlots: [
            .fixed(.ctrlC),
            .fixed(.ctrlO),
            .fixed(.backtick),
            .fixed(.enter),
        ]
    )

    func normalized() -> KeyboardBarLayout {
        var left = leftSlots
        var right = rightSlots

        if left.count > Self.leftSlotCount {
            left = Array(left.prefix(Self.leftSlotCount))
        } else if left.count < Self.leftSlotCount {
            left.append(contentsOf: Array(repeating: .fixed(.empty), count: Self.leftSlotCount - left.count))
        }

        if right.count > Self.rightSlotCount {
            right = Array(right.prefix(Self.rightSlotCount))
        } else if right.count < Self.rightSlotCount {
            right.append(contentsOf: Array(repeating: .fixed(.empty), count: Self.rightSlotCount - right.count))
        }

        return KeyboardBarLayout(leftSlots: left, rightSlots: right)
    }
}

enum KeyboardBarLayoutStore {
    static let userDefaultsKey = "keyboardBarLayout.v1"

    static func load() -> KeyboardBarLayout {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            let layout = KeyboardBarLayout.default.normalized()
            save(layout)
            return layout
        }

        do {
            let decoded = try JSONDecoder().decode(KeyboardBarLayout.self, from: data).normalized()
            save(decoded)
            return decoded
        } catch {
            let layout = KeyboardBarLayout.default.normalized()
            save(layout)
            return layout
        }
    }

    static func save(_ layout: KeyboardBarLayout) {
        let normalized = layout.normalized()
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    static func reset() {
        save(.default)
    }
}

extension Notification.Name {
    static let keyboardBarLayoutChanged = Notification.Name("com.clauntty.keyboardBarLayoutChanged")
}

/// Keyboard accessory bar with terminal-specific keys and arrow "nipple"
/// iOS Notes-style pill shape with fixed center nipple and evenly distributed buttons
/// Uses UIGlassEffect on iOS 26+ or UIBlurEffect fallback for native look
class KeyboardAccessoryView: UIView {

    /// Callback for sending key data to the terminal
    var onKeyInput: ((Data) -> Void)?

    /// Callback to dismiss keyboard (resign first responder)
    var onDismissKeyboard: (() -> Void)?

    /// Callback to show keyboard (become first responder)
    var onShowKeyboard: (() -> Void)?

    /// Callback for voice input (transcribed text)
    var onVoiceInput: ((String) -> Void)?

    /// Callback to prompt model download (when mic tapped but model not ready)
    var onPromptModelDownload: (() -> Void)?

    /// Callback to start recording
    var onStartRecording: (() -> Void)?

    /// Callback to stop recording and transcribe
    var onStopRecording: (() -> Void)?

    /// Callback to cancel recording without transcribing
    var onCancelRecording: (() -> Void)?

    /// Callback when joystick is double-tapped
    var onJoystickDoubleTap: (() -> Void)?

    /// Whether Ctrl modifier is active (sticky toggle)
    private var isCtrlActive = false {
        didSet {
            updateCtrlButton()
        }
    }

    /// Whether Option modifier is active (held via long-press on Ctrl)
    private var isOptionActive = false

    /// Whether Fn modifier is active (sticky toggle for next key/action)
    private var isFnActive = false {
        didSet {
            updateFnButton()
        }
    }

    /// Currently visible tooltip (for hold-down feedback)
    private var activeTooltip: HoldTooltip?

    /// Track if keyboard is currently visible (for icon state)
    private(set) var isKeyboardShown = true

    /// Track if mic is currently recording
    private(set) var isRecording = false {
        didSet {
            updateMicButtonAppearance()
            // Clear or show glow based on recording state
            if isRecording {
                animateGlowOn()
            } else {
                clearGlowImmediately()
            }
        }
    }

    /// Track if speech model is ready
    private(set) var isSpeechModelReady = false {
        didSet {
            updateMicButtonAppearance()
        }
    }

    /// Track if speech model is downloading
    private(set) var isSpeechModelDownloading = false {
        didSet {
            updateMicButtonAppearance()
            updateDownloadProgressVisibility()
        }
    }

    /// Download progress (0-1)
    private(set) var downloadProgress: Float = 0 {
        didSet {
            updateDownloadProgress()
        }
    }

    /// Track mic touch start time to differentiate tap vs hold
    private var micTouchStartTime: Date?

    /// Timer that fires when hold threshold is reached (starts push-to-talk)
    private var micHoldTimer: Timer?

    /// Whether we're in push-to-talk mode (started via hold, not tap)
    private var isPushToTalkMode = false

    /// Threshold to distinguish tap from hold (seconds)
    private let holdThreshold: TimeInterval = 0.2

    // MARK: - Views

    /// Main container (pill-shaped glass effect)
    private let containerEffectView: UIVisualEffectView = {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            effect = glassEffect
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }
        let view = UIVisualEffectView(effect: effect)
        view.clipsToBounds = true
        return view
    }()

    /// Left stack view for buttons before nipple
    private let leftStackView = UIStackView()

    /// Right stack view for buttons after nipple
    private let rightStackView = UIStackView()

    /// Fixed center nipple container
    private let nippleContainerView = UIView()

    /// The arrow nipple
    private let nippleView = ArrowNippleView()

    /// Ctrl button reference for state updates
    private var ctrlButton: UIButton?

    /// Ctrl container reference for expanded hit area
    private var ctrlContainer: UIView?

    /// Tab button reference for tooltip positioning
    private var tabButton: UIButton?

    /// Tab container reference for expanded hit area
    private var tabContainer: UIView?

    /// Mic button (voice input)
    private var micButton: UIButton?

    /// Fn button reference for state updates
    private var fnButton: UIButton?

    /// Progress indicator for model download
    private let downloadProgressView = CircularProgressView()

    /// Container for mic button and progress indicator
    private var micContainer: UIStackView?

    /// Spacer views for equal edge spacing (equalSpacing distribution needs items at edges)
    private let leftLeadingSpacer = UIView()
    private let leftTrailingSpacer = UIView()
    private let rightLeadingSpacer = UIView()
    private let rightTrailingSpacer = UIView()

    /// Invisible gesture zone at top of bar for keyboard show/hide gestures
    private let dragGestureZoneView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    /// Shadow host view for glow effect (UIVisualEffectView clips shadows)
    private let shadowHostView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    /// Glow layer inside shadow host (casts the colored shadow)
    private let glowLayer = CALayer()

    /// Glow color for recording
    private let glowColor: UIColor = .systemBlue

    /// Combine subscriptions for audio level updates
    private var cancellables = Set<AnyCancellable>()
    private var keyboardLayoutObserver: NSObjectProtocol?
    private var downloadProgressConstraintsConfigured = false

    // MARK: - Constraints

    private var containerLeadingConstraint: NSLayoutConstraint!
    private var containerTrailingConstraint: NSLayoutConstraint!
    private var containerWidthConstraint: NSLayoutConstraint!
    private var containerCenterXConstraint: NSLayoutConstraint!

    // MARK: - Constants

    private let barHeight: CGFloat = 52
    private let nippleSize: CGFloat = 36
    private let horizontalPadding: CGFloat = 12
    private let iconSize: CGFloat = 12
    private let textSize: CGFloat = 14
    private let topPadding: CGFloat = 0
    private let bottomPadding: CGFloat = 0
    private let collapsedWidth: CGFloat = 110  // keyboard button + nipple + padding
    private let dragGestureZoneHeight: CGFloat = 16

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    deinit {
        if let observer = keyboardLayoutObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupView() {
        backgroundColor = .clear

        setupContainerView()
        setupGlowEffect()  // Setup shadow-based glow on container
        setupGestureZone()
        setupNipple()
        setupStackViews()
        applyLayout(KeyboardBarLayoutStore.load())
        setupConstraints()
        setupDismissGestures()
        setupAudioLevelObserver()
        setupKeyboardLayoutObserver()
    }

    // MARK: - Gesture Zone Setup

    private func setupGestureZone() {
        dragGestureZoneView.translatesAutoresizingMaskIntoConstraints = false
        containerEffectView.contentView.addSubview(dragGestureZoneView)
    }

    // MARK: - Glow Effect Setup

    private func setupGlowEffect() {
        // Inner border for crisp edge (pulses with audio)
        containerEffectView.layer.borderWidth = 0
        containerEffectView.layer.borderColor = UIColor.systemBlue.cgColor

        // Glow layer - colored layer that casts the shadow
        glowLayer.backgroundColor = UIColor.clear.cgColor
        glowLayer.cornerRadius = barHeight / 2
        shadowHostView.layer.insertSublayer(glowLayer, at: 0)

        // Shadow properties on the shadow host
        shadowHostView.layer.cornerRadius = barHeight / 2
        shadowHostView.layer.shadowColor = UIColor.systemBlue.cgColor
        shadowHostView.layer.shadowRadius = 15
        shadowHostView.layer.shadowOpacity = 0
        shadowHostView.layer.shadowOffset = .zero
    }

    private func setupAudioLevelObserver() {
        SpeechManager.shared.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.updateGlowForAudioLevel(level)
            }
            .store(in: &cancellables)
    }

    // MARK: - Container Setup

    private func setupContainerView() {
        // Add shadow host view BEHIND container (for glow effect)
        shadowHostView.translatesAutoresizingMaskIntoConstraints = false
        shadowHostView.layer.cornerRadius = barHeight / 2
        addSubview(shadowHostView)

        // Add container on top
        containerEffectView.layer.cornerRadius = barHeight / 2
        containerEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerEffectView)
    }

    private func setupNipple() {
        // Nipple is added to containerEffectView so it moves with the container during drag
        nippleContainerView.translatesAutoresizingMaskIntoConstraints = false
        containerEffectView.contentView.addSubview(nippleContainerView)

        nippleView.onArrowInput = { [weak self] direction in
            self?.sendArrow(direction)
        }
        nippleView.onDoubleTap = { [weak self] in
            self?.onJoystickDoubleTap?()
        }
        nippleView.translatesAutoresizingMaskIntoConstraints = false
        nippleContainerView.addSubview(nippleView)
    }

    private func setupStackViews() {
        // Left stack view - evenly distributed, centered vertically
        leftStackView.axis = .horizontal
        leftStackView.distribution = .equalSpacing
        leftStackView.alignment = .center
        leftStackView.translatesAutoresizingMaskIntoConstraints = false
        containerEffectView.contentView.addSubview(leftStackView)

        // Right stack view - evenly distributed, centered vertically
        rightStackView.axis = .horizontal
        rightStackView.distribution = .equalSpacing
        rightStackView.alignment = .center
        rightStackView.translatesAutoresizingMaskIntoConstraints = false
        containerEffectView.contentView.addSubview(rightStackView)
    }

    private func setupKeyboardLayoutObserver() {
        keyboardLayoutObserver = NotificationCenter.default.addObserver(
            forName: .keyboardBarLayoutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.applyLayout(KeyboardBarLayoutStore.load())
        }
    }

    private func applyLayout(_ layout: KeyboardBarLayout) {
        // Clear arranged subviews before rebuilding
        for view in leftStackView.arrangedSubviews {
            leftStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in rightStackView.arrangedSubviews {
            rightStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        tabButton = nil
        tabContainer = nil
        ctrlButton = nil
        ctrlContainer = nil
        fnButton = nil
        micButton = nil
        micContainer = nil

        leftStackView.addArrangedSubview(UIView())
        for action in layout.leftSlots {
            leftStackView.addArrangedSubview(makeView(for: action))
        }
        leftStackView.addArrangedSubview(UIView())

        rightStackView.addArrangedSubview(UIView())
        for action in layout.rightSlots {
            rightStackView.addArrangedSubview(makeView(for: action))
        }
        rightStackView.addArrangedSubview(UIView())

        updateCtrlButton()
        updateMicButtonAppearance()
        updateDownloadProgressVisibility()
        updateDownloadProgress()
    }

    private func makeView(for action: KeyboardBarAction) -> UIView {
        let holdAction = action.holdAction

        switch action.kind {
        case .empty:
            let spacer = UIView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                spacer.widthAnchor.constraint(equalToConstant: 20),
                spacer.heightAnchor.constraint(equalToConstant: 20),
            ])
            return spacer
        case .mic:
            return makeMicActionView()
        case .esc:
            let button = createIconButton("escape", accessibilityId: "Esc", tooltip: "esc", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                self?.sendEscape()
            }
            return createButtonWithHint(button, hint: nil)
        case .tab:
            return makeTabActionView(action: action)
        case .ctrl:
            return makeCtrlActionView(action: action)
        case .fn:
            let button = createTextButton("Fn", accessibilityId: "Fn", tooltip: "Fn", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                self?.toggleFn()
            }
            fnButton = button
            updateFnButton()
            return button
        case .ctrlC:
            return createTextButton("^C", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }, action: { [weak self] in self?.sendCtrlC() })
        case .ctrlO:
            return createTextButton("^O", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }, action: { [weak self] in self?.sendCtrlO() })
        case .ctrlB:
            return createTextButton("^B", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }, action: { [weak self] in self?.sendCtrlB() })
        case .enter:
            return createIconButton("return", accessibilityId: "Enter", tooltip: "↵", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                self?.sendEnter()
            }
        case .backtick:
            return createTextButton("`", accessibilityId: "Backtick", tooltip: "`", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                self?.sendText("`")
            }
        case .up:
            return createTextButton("↑", accessibilityId: "Up", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendArrow(.up) }
        case .down:
            return createTextButton("↓", accessibilityId: "Down", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendArrow(.down) }
        case .left:
            return createTextButton("←", accessibilityId: "Left", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendArrow(.left) }
        case .right:
            return createTextButton("→", accessibilityId: "Right", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendArrow(.right) }
        case .home:
            return createTextButton("Home", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x48]) }
        case .end:
            return createTextButton("End", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x46]) }
        case .pageUp:
            return createTextButton("PgUp", accessibilityId: "PageUp", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                self?.sendEscapeSequence([0x1B, 0x5B, 0x35, 0x7E])
            }
        case .pageDown:
            return createTextButton("PgDn", accessibilityId: "PageDown", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                self?.sendEscapeSequence([0x1B, 0x5B, 0x36, 0x7E])
            }
        case .backspace:
            return createTextButton("⌫", accessibilityId: "Backspace", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }, repeatAction: { [weak self] in
                self?.sendEscapeSequence([0x7F])
            }) { [weak self] in
                self?.sendEscapeSequence([0x7F])
            }
        case .deleteForward:
            return createTextButton("⌦", accessibilityId: "DeleteForward", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                self?.sendEscapeSequence([0x1B, 0x5B, 0x33, 0x7E])
            }
        case .f1:
            return createTextButton("F1", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x4F, 0x50]) }
        case .f2:
            return createTextButton("F2", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x4F, 0x51]) }
        case .f3:
            return createTextButton("F3", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x4F, 0x52]) }
        case .f4:
            return createTextButton("F4", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x4F, 0x53]) }
        case .f5:
            return createTextButton("F5", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x31, 0x35, 0x7E]) }
        case .f6:
            return createTextButton("F6", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x31, 0x37, 0x7E]) }
        case .f7:
            return createTextButton("F7", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x31, 0x38, 0x7E]) }
        case .f8:
            return createTextButton("F8", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x31, 0x39, 0x7E]) }
        case .f9:
            return createTextButton("F9", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x32, 0x30, 0x7E]) }
        case .f10:
            return createTextButton("F10", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x32, 0x31, 0x7E]) }
        case .f11:
            return createTextButton("F11", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x32, 0x33, 0x7E]) }
        case .f12:
            return createTextButton("F12", holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in self?.sendEscapeSequence([0x1B, 0x5B, 0x32, 0x34, 0x7E]) }
        case .snippet:
            let snippet = action.snippetText ?? ""
            let runOnTap = action.snippetRunOnTap ?? false
            let title = action.snippetLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? action.snippetLabel!
                : "Snippet"
            return createTextButton(title, accessibilityId: "Snippet", tooltip: title, holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                guard !snippet.isEmpty else { return }
                self?.sendText(runOnTap ? "\(snippet)\r" : snippet)
            }
        case .customKey:
            let text = action.customText ?? ""
            let trimmedLabel = action.customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (trimmedLabel?.isEmpty == false ? trimmedLabel! : (text.isEmpty ? "Key" : text))
            return createTextButton(title, accessibilityId: "CustomKey", tooltip: title, holdTooltip: holdAction?.kind.title, holdAction: { [weak self] in
                guard let self, let holdAction else { return }
                self.performConfiguredAction(holdAction)
            }) { [weak self] in
                guard !text.isEmpty else { return }
                self?.sendText(text)
            }
        }
    }

    private func makeMicActionView() -> UIView {
        let button = UIButton(type: .system)
        button.tintColor = .label
        button.accessibilityIdentifier = "Mic"
        button.addTarget(self, action: #selector(micTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(micTouchUp), for: [.touchUpInside, .touchUpOutside])
        button.addTarget(self, action: #selector(micTouchCancelled), for: .touchCancel)
        micButton = button
        updateMicButtonAppearance()

        downloadProgressView.isHidden = true
        downloadProgressView.translatesAutoresizingMaskIntoConstraints = false

        let micContainerStack = createButtonWithHint(button, hint: nil)
        let micWithProgress = UIStackView(arrangedSubviews: [micContainerStack, downloadProgressView])
        micWithProgress.axis = .vertical
        micWithProgress.alignment = .center
        micWithProgress.spacing = 2

        if !downloadProgressConstraintsConfigured {
            NSLayoutConstraint.activate([
                downloadProgressView.widthAnchor.constraint(equalToConstant: 24),
                downloadProgressView.heightAnchor.constraint(equalToConstant: 4),
            ])
            downloadProgressConstraintsConfigured = true
        }

        micContainer = micWithProgress
        return micWithProgress
    }

    private func makeTabActionView(action: KeyboardBarAction) -> UIView {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "arrow.right.to.line")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            ),
            for: .normal
        )
        button.tintColor = .label
        button.accessibilityIdentifier = "Tab"
        button.isAccessibilityElement = true
        button.isUserInteractionEnabled = false
        tabButton = button

        let container = createButtonWithHint(button, hint: "⇧⇥")
        let holdAction = action.holdAction
        let holdButton = HoldableButton(type: .custom)
        holdButton.translatesAutoresizingMaskIntoConstraints = false
        holdButton.backgroundColor = .clear
        holdButton.onTap = { [weak self] in
            guard let self else { return }
            self.showTooltip(above: button, text: "⇥")
            self.hideTooltipAfterDelay()
            self.sendTab()
        }
        holdButton.onHold = { [weak self] in
            guard let self else { return }
            if let holdAction {
                self.performConfiguredAction(holdAction)
            } else {
                self.sendShiftTab()
                self.showTooltip(above: button, text: "⇧⇥")
            }
        }
        holdButton.onTouchDown = { [weak self] in
            self?.showTooltip(above: button, text: "⇥")
        }
        holdButton.onTouchRelease = { [weak self] in
            self?.hideTooltipAfterDelay()
        }
        container.addSubview(holdButton)
        NSLayoutConstraint.activate([
            holdButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            holdButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            holdButton.topAnchor.constraint(equalTo: container.topAnchor),
            holdButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        tabContainer = container
        return container
    }

    private func makeCtrlActionView(action: KeyboardBarAction) -> UIView {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "control")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            ),
            for: .normal
        )
        button.tintColor = .label
        button.accessibilityIdentifier = "Ctrl"
        button.isAccessibilityElement = true
        button.isUserInteractionEnabled = false
        ctrlButton = button

        let container = createButtonWithHint(button, hint: "⌥")
        let holdAction = action.holdAction
        let holdButton = HoldableButton(type: .custom)
        holdButton.translatesAutoresizingMaskIntoConstraints = false
        holdButton.backgroundColor = .clear
        holdButton.onTap = { [weak self] in
            self?.handleCtrlTap()
        }
        holdButton.onHold = { [weak self] in
            guard let self else { return }
            if let holdAction {
                self.performConfiguredAction(holdAction)
            } else {
                self.handleCtrlDefaultLongPress()
            }
        }
        holdButton.onTouchDown = { [weak self] in
            self?.showTooltip(above: button, text: self?.isOptionActive == true ? "⌥" : "⌃")
        }
        holdButton.onTouchRelease = { [weak self] in
            self?.hideTooltipAfterDelay()
        }
        container.addSubview(holdButton)
        NSLayoutConstraint.activate([
            holdButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            holdButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            holdButton.topAnchor.constraint(equalTo: container.topAnchor),
            holdButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        ctrlContainer = container
        return container
    }

    private func setupConstraints() {
        // Container view - pill shape
        // Expanded mode: leading/trailing constraints
        containerLeadingConstraint = containerEffectView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding)
        containerTrailingConstraint = containerEffectView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding)

        // Collapsed mode: centered with fixed width
        containerCenterXConstraint = containerEffectView.centerXAnchor.constraint(equalTo: centerXAnchor)
        containerWidthConstraint = containerEffectView.widthAnchor.constraint(equalToConstant: collapsedWidth)
        containerCenterXConstraint.isActive = false
        containerWidthConstraint.isActive = false

        NSLayoutConstraint.activate([
            // Shadow host view - same position as container
            shadowHostView.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
            shadowHostView.heightAnchor.constraint(equalToConstant: barHeight),
            shadowHostView.leadingAnchor.constraint(equalTo: containerEffectView.leadingAnchor),
            shadowHostView.trailingAnchor.constraint(equalTo: containerEffectView.trailingAnchor),

            // Container view
            containerLeadingConstraint,
            containerTrailingConstraint,
            containerEffectView.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
            containerEffectView.heightAnchor.constraint(equalToConstant: barHeight),

            // Top gesture zone for keyboard show/hide
            dragGestureZoneView.topAnchor.constraint(equalTo: containerEffectView.contentView.topAnchor),
            dragGestureZoneView.leadingAnchor.constraint(equalTo: containerEffectView.contentView.leadingAnchor),
            dragGestureZoneView.trailingAnchor.constraint(equalTo: containerEffectView.contentView.trailingAnchor),
            dragGestureZoneView.heightAnchor.constraint(equalToConstant: dragGestureZoneHeight),

            // Nipple container - centered within container
            nippleContainerView.centerXAnchor.constraint(equalTo: containerEffectView.contentView.centerXAnchor),
            nippleContainerView.centerYAnchor.constraint(equalTo: containerEffectView.contentView.centerYAnchor),
            nippleContainerView.widthAnchor.constraint(equalToConstant: nippleSize),
            nippleContainerView.heightAnchor.constraint(equalToConstant: nippleSize),

            // Nipple view inside container
            nippleView.topAnchor.constraint(equalTo: nippleContainerView.topAnchor),
            nippleView.bottomAnchor.constraint(equalTo: nippleContainerView.bottomAnchor),
            nippleView.leadingAnchor.constraint(equalTo: nippleContainerView.leadingAnchor),
            nippleView.trailingAnchor.constraint(equalTo: nippleContainerView.trailingAnchor),

            // Left stack view - aligned with nipple (toward bottom)
            leftStackView.leadingAnchor.constraint(equalTo: containerEffectView.contentView.leadingAnchor, constant: 8),
            leftStackView.trailingAnchor.constraint(equalTo: nippleContainerView.leadingAnchor, constant: -4),
            leftStackView.centerYAnchor.constraint(equalTo: nippleContainerView.centerYAnchor),
            leftStackView.heightAnchor.constraint(equalToConstant: nippleSize),

            // Right stack view - aligned with nipple (toward bottom)
            rightStackView.leadingAnchor.constraint(equalTo: nippleContainerView.trailingAnchor, constant: 4),
            rightStackView.trailingAnchor.constraint(equalTo: containerEffectView.contentView.trailingAnchor, constant: -8),
            rightStackView.centerYAnchor.constraint(equalTo: nippleContainerView.centerYAnchor),
            rightStackView.heightAnchor.constraint(equalToConstant: nippleSize),
        ])
    }

    // MARK: - Layout

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            // Force layout update now that we have correct safe area from window
            updateConstraintsForSafeArea()
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateConstraintsForSafeArea()

        // Update glow layer frame to match shadow host
        glowLayer.frame = shadowHostView.bounds

        // Ensure proper z-ordering
        sendSubviewToBack(shadowHostView)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateConstraintsForSafeArea()
    }

    private func updateConstraintsForSafeArea() {
        let safeInsets: UIEdgeInsets
        if let window = window {
            safeInsets = window.safeAreaInsets
        } else {
            safeInsets = safeAreaInsets
        }

        containerLeadingConstraint.constant = max(horizontalPadding, safeInsets.left + horizontalPadding)
        containerTrailingConstraint.constant = -max(horizontalPadding, safeInsets.right + horizontalPadding)
    }

    // MARK: - Button Creation

    private func createIconButton(
        _ systemName: String,
        accessibilityId: String,
        tooltip: String? = nil,
        holdTooltip: String? = nil,
        holdAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = HoldableButton(type: .system)
        button.setImage(
            UIImage(systemName: systemName)?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            ),
            for: .normal
        )
        button.tintColor = .label
        button.accessibilityIdentifier = accessibilityId
        button.isAccessibilityElement = true
        button.onTap = action
        button.onTouchDown = { [weak self] in
            if let tooltipText = tooltip {
                self?.showTooltip(above: button, text: tooltipText)
            }
        }
        button.onTouchRelease = { [weak self] in
            self?.hideTooltipAfterDelay()
        }
        if let holdAction {
            button.onHold = { [weak self] in
                if let holdTooltip {
                    self?.showTooltip(above: button, text: holdTooltip)
                }
                holdAction()
            }
        }
        return button
    }

    private func createTextButton(
        _ title: String,
        accessibilityId: String? = nil,
        tooltip: String? = nil,
        holdTooltip: String? = nil,
        holdAction: (() -> Void)? = nil,
        repeatAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = HoldableButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: textSize, weight: .medium)
        button.setTitleColor(.label, for: .normal)
        button.accessibilityIdentifier = accessibilityId ?? title
        button.isAccessibilityElement = true
        button.onTap = action

        // Add tooltip feedback on touch
        let tooltipText = tooltip ?? title
        button.onTouchDown = { [weak self] in
            self?.showTooltip(above: button, text: tooltipText)
        }
        button.onTouchRelease = { [weak self] in
            self?.hideTooltipAfterDelay()
        }
        if let holdAction {
            button.onHold = { [weak self] in
                if let holdTooltip {
                    self?.showTooltip(above: button, text: holdTooltip)
                }
                holdAction()
            }
        }
        if let repeatAction {
            button.onRepeatTick = repeatAction
        }
        return button
    }

    private func createHintLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 8, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }

    private func createButtonWithHint(_ button: UIButton, hint: String?) -> UIStackView {
        let hintLabel = createHintLabel(hint ?? "")
        if hint == nil {
            hintLabel.alpha = 0  // Invisible spacer to maintain consistent height
        }
        let stack = UIStackView(arrangedSubviews: [button, hintLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1
        return stack
    }

    private func updateCtrlButton() {
        if isCtrlActive {
            ctrlButton?.tintColor = .systemBlue
        } else {
            ctrlButton?.tintColor = .label
        }
    }

    private func updateMicButtonAppearance() {
        let iconName: String
        let tintColor: UIColor

        if isRecording {
            iconName = "mic.fill"
            tintColor = UIColor.systemBlue.withAlphaComponent(0.8)  // Light blue tint
        } else if isSpeechModelDownloading {
            iconName = "mic.fill"
            tintColor = .systemBlue  // Blue while downloading
        } else {
            iconName = "mic.fill"
            tintColor = isSpeechModelReady ? .label : .secondaryLabel
        }

        micButton?.setImage(
            UIImage(systemName: iconName)?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            ),
            for: .normal
        )
        micButton?.tintColor = tintColor
    }

    /// Called when keyboard visibility changes externally
    func setKeyboardVisible(_ visible: Bool) {
        Logger.clauntty.debugOnly("[AccessoryBar] setKeyboardVisible(\(visible)) called, was=\(self.isKeyboardShown)")
        isKeyboardShown = visible
    }

    /// Update speech model ready state
    func setSpeechModelReady(_ ready: Bool) {
        isSpeechModelReady = ready
    }

    /// Update recording state (glow handled by didSet on isRecording)
    func setRecording(_ recording: Bool) {
        isRecording = recording
    }

    /// Immediately clear all glow effects (called when recording stops)
    private func clearGlowImmediately() {
        // Disable implicit animations for immediate effect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerEffectView.layer.borderWidth = 0
        containerEffectView.layer.borderColor = UIColor.clear.cgColor
        shadowHostView.layer.shadowOpacity = 0
        glowLayer.backgroundColor = UIColor.clear.cgColor
        CATransaction.commit()
    }

    /// Update speech model downloading state
    func setSpeechModelDownloading(_ downloading: Bool) {
        isSpeechModelDownloading = downloading
    }

    /// Update download progress (0-1)
    func setDownloadProgress(_ progress: Float) {
        downloadProgress = progress
    }

    private func updateDownloadProgressVisibility() {
        downloadProgressView.isHidden = !isSpeechModelDownloading
    }

    private func updateDownloadProgress() {
        downloadProgressView.progress = CGFloat(downloadProgress)
    }

    // MARK: - Glow Effect

    private func updateGlowForAudioLevel(_ level: Float) {
        guard isRecording else {
            return
        }

        // Scale level for visibility (audio levels are often low)
        let scaledLevel = min(level * 4, 1.0)

        // Map audio level to blue intensity
        // Low audio = subtle glow, high audio = strong glow
        let minBorderWidth: CGFloat = 1.0
        let maxBorderWidth: CGFloat = 3.5
        let minShadowOpacity: Float = 0.3
        let maxShadowOpacity: Float = 0.9
        let minShadowRadius: CGFloat = 8
        let maxShadowRadius: CGFloat = 20

        let borderWidth = minBorderWidth + CGFloat(scaledLevel) * (maxBorderWidth - minBorderWidth)
        let shadowOpacity = minShadowOpacity + scaledLevel * (maxShadowOpacity - minShadowOpacity)
        let shadowRadius = minShadowRadius + CGFloat(scaledLevel) * (maxShadowRadius - minShadowRadius)

        // Update border and shadow based on audio level
        containerEffectView.layer.borderWidth = borderWidth
        shadowHostView.layer.shadowOpacity = shadowOpacity
        shadowHostView.layer.shadowRadius = shadowRadius
        glowLayer.backgroundColor = glowColor.withAlphaComponent(CGFloat(shadowOpacity)).cgColor
    }

    private func animateGlowOn() {
        // Set blue color and initial glow
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        containerEffectView.layer.borderColor = glowColor.cgColor
        containerEffectView.layer.borderWidth = 1.0
        shadowHostView.layer.shadowColor = glowColor.cgColor
        shadowHostView.layer.shadowOpacity = 0.3
        glowLayer.backgroundColor = glowColor.withAlphaComponent(0.3).cgColor
        CATransaction.commit()
    }

    // MARK: - Dismiss Gestures

    private func setupDismissGestures() {
        // Keyboard show/hide gestures are on the top gesture zone

        // Swipe down = instant dismiss
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeToDismiss))
        swipeDown.direction = .down
        dragGestureZoneView.addGestureRecognizer(swipeDown)

        // Swipe up = instant show keyboard
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeToShow))
        swipeUp.direction = .up
        dragGestureZoneView.addGestureRecognizer(swipeUp)

        // Drag/pan = interactive dismiss/show
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        pan.delegate = self
        dragGestureZoneView.addGestureRecognizer(pan)

        // Tap to toggle keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleGestureZoneTap))
        dragGestureZoneView.addGestureRecognizer(tap)
    }

    @objc private func handleGestureZoneTap() {
        if isKeyboardShown {
            Logger.clauntty.debugOnly("[AccessoryBar] gesture zone tap to dismiss")
            onDismissKeyboard?()
        } else {
            Logger.clauntty.debugOnly("[AccessoryBar] gesture zone tap to show keyboard")
            onShowKeyboard?()
        }
    }

    @objc private func handleSwipeToDismiss(_ gesture: UISwipeGestureRecognizer) {
        Logger.clauntty.debugOnly("[AccessoryBar] swipe down to dismiss")
        onDismissKeyboard?()
    }

    @objc private func handleSwipeToShow(_ gesture: UISwipeGestureRecognizer) {
        Logger.clauntty.debugOnly("[AccessoryBar] swipe up to show keyboard")
        onShowKeyboard?()
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        switch gesture.state {
        case .changed:
            if translation.y > 0 {
                // Dragging down - move container down
                containerEffectView.transform = CGAffineTransform(translationX: 0, y: min(translation.y, 100))
            } else if translation.y < 0 {
                // Dragging up - move container up slightly for feedback
                containerEffectView.transform = CGAffineTransform(translationX: 0, y: max(translation.y, -30))
            }
        case .ended, .cancelled:
            if translation.y > 0 {
                // Was dragging down - dismiss if far enough
                let shouldDismiss = translation.y > 50 || velocity.y > 500

                if shouldDismiss {
                    UIView.animate(withDuration: 0.2) {
                        self.containerEffectView.transform = CGAffineTransform(translationX: 0, y: 100)
                    } completion: { _ in
                        self.containerEffectView.transform = .identity
                        self.onDismissKeyboard?()
                    }
                } else {
                    // Snap back
                    UIView.animate(withDuration: 0.2) {
                        self.containerEffectView.transform = .identity
                    }
                }
            } else if translation.y < 0 {
                // Was dragging up - show keyboard if far enough
                let shouldShow = translation.y < -30 || velocity.y < -500

                UIView.animate(withDuration: 0.2) {
                    self.containerEffectView.transform = .identity
                }

                if shouldShow {
                    Logger.clauntty.debugOnly("[AccessoryBar] drag up to show keyboard")
                    onShowKeyboard?()
                }
            } else {
                UIView.animate(withDuration: 0.2) {
                    self.containerEffectView.transform = .identity
                }
            }
        default:
            break
        }
    }

    // MARK: - Mic Button Actions

    @objc private func micTouchDown() {
        micTouchStartTime = Date()
        isPushToTalkMode = false

        // If model not ready or downloading, we'll handle on touch up
        guard isSpeechModelReady, !isSpeechModelDownloading else { return }

        // If already recording (toggle mode), don't start a new timer
        guard !isRecording else { return }

        // Start timer - if user holds past threshold, start push-to-talk recording
        micHoldTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isPushToTalkMode = true
            self.startRecordingWithFeedback()
            Logger.clauntty.debugOnly("[AccessoryBar] hold threshold reached, starting push-to-talk recording")
        }
    }

    @objc private func micTouchUp() {
        guard micTouchStartTime != nil else { return }
        micTouchStartTime = nil

        // Cancel the hold timer if it hasn't fired yet
        micHoldTimer?.invalidate()
        micHoldTimer = nil

        // If model is downloading, show status tooltip instead of re-prompting
        if isSpeechModelDownloading {
            let progressPercent = Int(downloadProgress * 100)
            if let micButton = micButton {
                showTooltip(above: micButton, text: "Downloading... \(progressPercent)%")
            }
            hideTooltipAfterDelay(delay: 1.5)
            Logger.clauntty.debugOnly("[AccessoryBar] mic tap during download, progress: \(progressPercent)%")
            return
        }

        // If model not ready, prompt download
        guard isSpeechModelReady else {
            Logger.clauntty.debugOnly("[AccessoryBar] mic tap, model not ready - prompting download")
            onPromptModelDownload?()
            return
        }

        if isPushToTalkMode {
            // Was in push-to-talk mode, stop and transcribe on release
            Logger.clauntty.debugOnly("[AccessoryBar] mic release, stopping push-to-talk recording")
            isRecording = false
            onStopRecording?()
        } else {
            // Tap mode - toggle recording
            if isRecording {
                // Was recording, stop and transcribe
                Logger.clauntty.debugOnly("[AccessoryBar] mic tap to stop recording (toggle mode)")
                isRecording = false
                onStopRecording?()
            } else {
                // Not recording, start recording (will stop on next tap)
                Logger.clauntty.debugOnly("[AccessoryBar] mic tap to start recording (toggle mode)")
                startRecordingWithFeedback()
            }
        }

        isPushToTalkMode = false
    }

    @objc private func micTouchCancelled() {
        micTouchStartTime = nil
        micHoldTimer?.invalidate()
        micHoldTimer = nil
        isPushToTalkMode = false

        if isRecording {
            onCancelRecording?()
            isRecording = false
            Logger.clauntty.debugOnly("[AccessoryBar] mic touch cancelled, recording stopped without transcription")
        }
    }

    private func startRecordingWithFeedback() {
        onStartRecording?()
        isRecording = true

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: - Key Actions

    private func performConfiguredAction(_ action: KeyboardBarAction) {
        switch action.kind {
        case .empty:
            return
        case .mic:
            return
        case .esc:
            sendEscape()
        case .tab:
            sendTab()
        case .ctrl:
            toggleCtrl()
        case .fn:
            toggleFn()
        case .ctrlC:
            sendCtrlC()
        case .ctrlO:
            sendCtrlO()
        case .ctrlB:
            sendCtrlB()
        case .enter:
            sendEnter()
        case .backtick:
            sendText("`")
        case .up:
            sendArrow(.up)
        case .down:
            sendArrow(.down)
        case .left:
            sendArrow(.left)
        case .right:
            sendArrow(.right)
        case .home:
            sendEscapeSequence([0x1B, 0x5B, 0x48])
        case .end:
            sendEscapeSequence([0x1B, 0x5B, 0x46])
        case .pageUp:
            sendEscapeSequence([0x1B, 0x5B, 0x35, 0x7E])
        case .pageDown:
            sendEscapeSequence([0x1B, 0x5B, 0x36, 0x7E])
        case .backspace:
            sendEscapeSequence([0x7F])
        case .deleteForward:
            sendEscapeSequence([0x1B, 0x5B, 0x33, 0x7E])
        case .f1:
            sendEscapeSequence([0x1B, 0x4F, 0x50])
        case .f2:
            sendEscapeSequence([0x1B, 0x4F, 0x51])
        case .f3:
            sendEscapeSequence([0x1B, 0x4F, 0x52])
        case .f4:
            sendEscapeSequence([0x1B, 0x4F, 0x53])
        case .f5:
            sendEscapeSequence([0x1B, 0x5B, 0x31, 0x35, 0x7E])
        case .f6:
            sendEscapeSequence([0x1B, 0x5B, 0x31, 0x37, 0x7E])
        case .f7:
            sendEscapeSequence([0x1B, 0x5B, 0x31, 0x38, 0x7E])
        case .f8:
            sendEscapeSequence([0x1B, 0x5B, 0x31, 0x39, 0x7E])
        case .f9:
            sendEscapeSequence([0x1B, 0x5B, 0x32, 0x30, 0x7E])
        case .f10:
            sendEscapeSequence([0x1B, 0x5B, 0x32, 0x31, 0x7E])
        case .f11:
            sendEscapeSequence([0x1B, 0x5B, 0x32, 0x33, 0x7E])
        case .f12:
            sendEscapeSequence([0x1B, 0x5B, 0x32, 0x34, 0x7E])
        case .snippet:
            guard let text = action.snippetText, !text.isEmpty else { return }
            if action.snippetRunOnTap ?? false {
                sendText("\(text)\r")
            } else {
                sendText(text)
            }
        case .customKey:
            guard let text = action.customText, !text.isEmpty else { return }
            sendText(text)
        }
    }

    private func sendEscape() {
        sendKeyData(Data([0x1B]))
    }

    private func sendTab() {
        sendKeyData(Data([0x09]))
    }

    @objc private func handleCtrlTap() {
        // Show ⌃ for Ctrl, or ⌥ if deactivating Option
        let tooltipText = isOptionActive ? "⌥" : "⌃"
        if let ctrlButton = ctrlButton {
            showTooltip(above: ctrlButton, text: tooltipText)
        }
        hideTooltipAfterDelay()
        toggleCtrl()
    }

    private func handleCtrlDefaultLongPress() {
        if isOptionActive {
            // If Option already active, deactivate it
            isOptionActive = false
            resetToCtrlState()
        } else {
            // Clear Ctrl if active, activate Option (sticky)
            isCtrlActive = false
            isOptionActive = true
            showOptionState()
            if let ctrlButton = ctrlButton {
                showTooltip(above: ctrlButton, text: "⌥")
            }
        }
    }

    private func showOptionState() {
        UIView.animate(withDuration: 0.15) {
            self.ctrlButton?.transform = CGAffineTransform(translationX: 0, y: -3)
        }
        ctrlButton?.setImage(
            UIImage(systemName: "option")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            ),
            for: .normal
        )
        ctrlButton?.tintColor = .systemBlue
    }

    private func resetToCtrlState() {
        UIView.animate(withDuration: 0.15) {
            self.ctrlButton?.transform = .identity
        }
        ctrlButton?.setImage(
            UIImage(systemName: "control")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            ),
            for: .normal
        )
        updateCtrlButton()  // Restore correct color based on isCtrlActive
    }

    private func sendShiftTab() {
        // Shift+Tab = CSI Z (Back Tab / CBT)
        sendKeyData(Data([0x1B, 0x5B, 0x5A]))  // ESC [ Z
    }

    private func toggleCtrl() {
        // If Option is active, tapping deactivates Option
        if isOptionActive {
            isOptionActive = false
            resetToCtrlState()
            return
        }
        // Otherwise toggle Ctrl as normal
        isCtrlActive.toggle()
    }

    /// Check if Ctrl is active and consume the state
    /// Returns true if Ctrl was active (and clears it)
    func consumeCtrlModifier() -> Bool {
        if isCtrlActive {
            isCtrlActive = false
            return true
        }
        return false
    }

    /// Check if Option is active and consume the state
    /// Returns true if Option was active (and clears it)
    func consumeOptionModifier() -> Bool {
        if isOptionActive {
            isOptionActive = false
            resetToCtrlState()
            return true
        }
        return false
    }

    // MARK: - Tooltip

    private func showTooltip(above button: UIView, text: String) {
        hideTooltip()

        let tooltip = HoldTooltip(text: text)
        addSubview(tooltip)

        // Position tooltip above the button
        tooltip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tooltip.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            tooltip.bottomAnchor.constraint(equalTo: containerEffectView.topAnchor, constant: -4),
        ])

        // Animate in
        tooltip.alpha = 0
        tooltip.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.15) {
            tooltip.alpha = 1
            tooltip.transform = .identity
        }

        activeTooltip = tooltip
    }

    private func hideTooltip() {
        guard let tooltip = activeTooltip else { return }
        UIView.animate(withDuration: 0.1, animations: {
            tooltip.alpha = 0
            tooltip.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }, completion: { _ in
            tooltip.removeFromSuperview()
        })
        activeTooltip = nil
    }

    private func hideTooltipAfterDelay(delay: TimeInterval = 0.1) {
        // Brief delay so the tooltip is visible momentarily
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.hideTooltip()
        }
    }

    private func sendArrow(_ direction: ArrowNippleView.Direction) {
        if consumeFnModifier() {
            switch direction {
            case .up:
                sendEscapeSequence([0x1B, 0x5B, 0x35, 0x7E])  // PgUp
            case .down:
                sendEscapeSequence([0x1B, 0x5B, 0x36, 0x7E])  // PgDn
            case .right:
                sendEscapeSequence([0x1B, 0x5B, 0x46])  // End
            case .left:
                sendEscapeSequence([0x1B, 0x5B, 0x48])  // Home
            }
            return
        }

        let data: Data
        switch direction {
        case .up:
            data = Data([0x1B, 0x5B, 0x41])    // ESC [ A
        case .down:
            data = Data([0x1B, 0x5B, 0x42])    // ESC [ B
        case .right:
            data = Data([0x1B, 0x5B, 0x43])    // ESC [ C
        case .left:
            data = Data([0x1B, 0x5B, 0x44])    // ESC [ D
        }
        sendKeyData(data)

        // If Ctrl was active, clear it after use
        if isCtrlActive {
            isCtrlActive = false
        }
    }

    private func sendCtrlC() {
        sendKeyData(Data([0x03]))  // ETX
    }

    private func sendCtrlO() {
        sendKeyData(Data([0x0F]))  // SI (Ctrl+O)
    }

    private func sendCtrlB() {
        sendKeyData(Data([0x02]))  // STX (Ctrl+B)
    }

    private func sendEnter() {
        sendKeyData(Data([0x0D]))  // CR (Return/Enter)
    }

    private func sendEscapeSequence(_ bytes: [UInt8]) {
        sendKeyData(Data(bytes))
    }

    private func sendText(_ text: String) {
        if consumeFnModifier() {
            if let mapped = mappedFnData(for: text) {
                sendKeyData(mapped)
                return
            }
        }
        if let data = text.data(using: .utf8) {
            sendKeyData(data)
        }
    }

    private func sendKeyData(_ data: Data) {
        onKeyInput?(data)
    }

    private func toggleFn() {
        isFnActive.toggle()
    }

    private func updateFnButton() {
        fnButton?.tintColor = isFnActive ? .systemBlue : .label
    }

    /// Check if Fn is active and consume it for one-shot behavior.
    func consumeFnModifier() -> Bool {
        if isFnActive {
            isFnActive = false
            return true
        }
        return false
    }

    /// Map Fn+character to terminal function key escape sequences.
    func mappedFnData(for text: String) -> Data? {
        guard text.count == 1 else { return nil }
        guard let char = text.first else { return nil }
        return Self.fnMappedData(for: char)
    }

    static func fnMappedData(for char: Character) -> Data? {
        switch char {
        case "1": return Data([0x1B, 0x4F, 0x50]) // F1
        case "2": return Data([0x1B, 0x4F, 0x51]) // F2
        case "3": return Data([0x1B, 0x4F, 0x52]) // F3
        case "4": return Data([0x1B, 0x4F, 0x53]) // F4
        case "5": return Data([0x1B, 0x5B, 0x31, 0x35, 0x7E]) // F5
        case "6": return Data([0x1B, 0x5B, 0x31, 0x37, 0x7E]) // F6
        case "7": return Data([0x1B, 0x5B, 0x31, 0x38, 0x7E]) // F7
        case "8": return Data([0x1B, 0x5B, 0x31, 0x39, 0x7E]) // F8
        case "9": return Data([0x1B, 0x5B, 0x32, 0x30, 0x7E]) // F9
        case "0": return Data([0x1B, 0x5B, 0x32, 0x31, 0x7E]) // F10
        case "-": return Data([0x1B, 0x5B, 0x32, 0x33, 0x7E]) // F11
        case "=": return Data([0x1B, 0x5B, 0x32, 0x34, 0x7E]) // F12
        default:
            return nil
        }
    }

    override var intrinsicContentSize: CGSize {
        // topPadding above bar + barHeight + bottomPadding
        return CGSize(width: UIView.noIntrinsicMetric, height: topPadding + barHeight + bottomPadding)
    }

    // MARK: - Touch Handling

    /// Horizontal padding to expand hit areas for Tab and Ctrl buttons
    private let expandedHitPadding: CGFloat = 12

    /// Override hitTest to expand vertical hit areas for all buttons
    /// and horizontal hit areas for Tab and Ctrl
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Hidden views must not receive touches
        // UIKit normally skips hidden views, but we override hitTest so we must check manually
        guard !isHidden else { return nil }

        // Check nipple - it's on top and overlaps the container
        let nippleFrame = nippleContainerView.frame
        if nippleFrame.contains(point) {
            let nipplePoint = convert(point, to: nippleContainerView)
            if let hitView = nippleContainerView.hitTest(nipplePoint, with: event) {
                Logger.clauntty.verbose("[AccessoryBar] hitTest: hit nipple subview")
                return hitView
            }
            Logger.clauntty.verbose("[AccessoryBar] hitTest: hit nipple background")
            return nippleContainerView
        }

        // Check if touch is within the horizontal bounds of the container
        // but expand vertical bounds to the full bar area
        let containerFrame = containerEffectView.frame
        let expandedFrame = CGRect(
            x: containerFrame.minX,
            y: bounds.minY,
            width: containerFrame.width,
            height: bounds.height
        )

        if expandedFrame.contains(point) {
            // Check top gesture zone first
            let gestureZoneFrameInSelf = dragGestureZoneView.convert(dragGestureZoneView.bounds, to: self)
            if gestureZoneFrameInSelf.contains(point) {
                Logger.clauntty.verbose("[AccessoryBar] hitTest: hit gesture zone")
                return dragGestureZoneView
            }

            // Check expanded hit areas for Ctrl and Tab first (they need wider touch targets)
            if let ctrl = ctrlContainer {
                let ctrlFrame = ctrl.convert(ctrl.bounds, to: self)
                let expandedCtrlFrame = ctrlFrame.insetBy(dx: -expandedHitPadding, dy: 0)
                    .union(CGRect(x: ctrlFrame.minX - expandedHitPadding, y: bounds.minY,
                                  width: ctrlFrame.width + expandedHitPadding * 2, height: bounds.height))
                if expandedCtrlFrame.contains(point) {
                    Logger.clauntty.verbose("[AccessoryBar] hitTest: expanded Ctrl hit")
                    return ctrl
                }
            }

            if let tab = tabContainer {
                let tabFrame = tab.convert(tab.bounds, to: self)
                let expandedTabFrame = CGRect(x: tabFrame.minX - expandedHitPadding, y: bounds.minY,
                                              width: tabFrame.width + expandedHitPadding * 2, height: bounds.height)
                if expandedTabFrame.contains(point) {
                    Logger.clauntty.verbose("[AccessoryBar] hitTest: expanded Tab hit")
                    return tab
                }
            }

            // Expanded hit area for mic button (larger touch target for speech-to-text)
            if let mic = micContainer {
                let micFrame = mic.convert(mic.bounds, to: self)
                // Extra padding for mic - it's an important button
                let micPadding: CGFloat = 16
                let expandedMicFrame = CGRect(x: micFrame.minX - micPadding, y: bounds.minY,
                                              width: micFrame.width + micPadding * 2, height: bounds.height)
                if expandedMicFrame.contains(point) {
                    Logger.clauntty.verbose("[AccessoryBar] hitTest: expanded Mic hit")
                    return micButton
                }
            }

            // Find which button is at this horizontal position by checking both stacks
            // Use the center Y of the container for the hit test
            let centerY = containerFrame.midY
            let adjustedPoint = CGPoint(x: point.x, y: centerY)
            let containerPoint = convert(adjustedPoint, to: containerEffectView)

            if let hitView = containerEffectView.hitTest(containerPoint, with: event) {
                Logger.clauntty.verbose("[AccessoryBar] hitTest: expanded hit on \(String(describing: type(of: hitView)))")
                return hitView
            }

            // If no subview handles it, return the container itself
            Logger.clauntty.verbose("[AccessoryBar] hitTest: hit container background (expanded)")
            return containerEffectView
        }

        // Touch is outside visible elements - pass through to views below
        Logger.clauntty.verbose("[AccessoryBar] hitTest: passing through at \(Int(point.x)),\(Int(point.y))")
        return nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension KeyboardAccessoryView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pan gesture to work with other gestures
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only begin pan if it's primarily vertical (for keyboard show/hide)
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: self)
            // Allow both up and down vertical gestures on the top gesture zone
            return abs(velocity.y) > abs(velocity.x)
        }
        return true
    }
}

// MARK: - Collapsed Keyboard Bar

/// Floating mini bar shown when keyboard is hidden
/// Contains just the keyboard show button and arrow nipple
class CollapsedKeyboardBar: UIView {

    /// Callback to show keyboard
    var onShowKeyboard: (() -> Void)?

    /// Callback for arrow input
    var onArrowInput: ((ArrowNippleView.Direction) -> Void)?

    // MARK: - Views

    private let containerEffectView: UIVisualEffectView = {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            effect = glassEffect
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }
        let view = UIVisualEffectView(effect: effect)
        view.clipsToBounds = true
        return view
    }()

    private let keyboardButton = UIButton(type: .system)
    private let nippleView = ArrowNippleView()

    // MARK: - Constants

    private let barHeight: CGFloat = 44
    private let nippleSize: CGFloat = 36
    private let iconSize: CGFloat = 14

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .clear

        // Container - pill shape
        containerEffectView.layer.cornerRadius = barHeight / 2
        containerEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerEffectView)

        // Keyboard button
        keyboardButton.setImage(
            UIImage(systemName: "keyboard")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            ),
            for: .normal
        )
        keyboardButton.tintColor = .label
        keyboardButton.addAction(UIAction { [weak self] _ in
            self?.onShowKeyboard?()
        }, for: .touchUpInside)
        keyboardButton.translatesAutoresizingMaskIntoConstraints = false
        containerEffectView.contentView.addSubview(keyboardButton)

        // Nipple
        nippleView.onArrowInput = { [weak self] direction in
            self?.onArrowInput?(direction)
        }
        nippleView.translatesAutoresizingMaskIntoConstraints = false
        containerEffectView.contentView.addSubview(nippleView)

        // Constraints
        NSLayoutConstraint.activate([
            // Container size
            containerEffectView.topAnchor.constraint(equalTo: topAnchor),
            containerEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerEffectView.heightAnchor.constraint(equalToConstant: barHeight),
            containerEffectView.widthAnchor.constraint(equalToConstant: barHeight + nippleSize + 16),

            // Keyboard button
            keyboardButton.leadingAnchor.constraint(equalTo: containerEffectView.contentView.leadingAnchor, constant: 12),
            keyboardButton.centerYAnchor.constraint(equalTo: containerEffectView.contentView.centerYAnchor),

            // Nipple
            nippleView.trailingAnchor.constraint(equalTo: containerEffectView.contentView.trailingAnchor, constant: -6),
            nippleView.centerYAnchor.constraint(equalTo: containerEffectView.contentView.centerYAnchor),
            nippleView.widthAnchor.constraint(equalToConstant: nippleSize),
            nippleView.heightAnchor.constraint(equalToConstant: nippleSize),
        ])
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: barHeight + nippleSize + 16, height: barHeight)
    }
}

// MARK: - Hold Tooltip

/// Button that supports primary tap + hold action without firing tap after hold.
private class HoldableButton: UIButton {
    var onTap: (() -> Void)?
    var onHold: (() -> Void)?
    var onRepeatTick: (() -> Void)?
    var onTouchDown: (() -> Void)?
    var onTouchRelease: (() -> Void)?

    private var holdTimer: Timer?
    private var repeatDelayTimer: Timer?
    private var repeatTimer: Timer?
    private var holdTriggered = false
    private var repeatTriggered = false
    private let holdThreshold: TimeInterval = 0.28
    private let repeatInitialDelay: TimeInterval = 0.24
    private let repeatInterval: TimeInterval = 0.055

    private func scheduleTimer(
        interval: TimeInterval,
        repeats: Bool,
        _ block: @escaping (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wireEvents()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wireEvents()
    }

    private func wireEvents() {
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUpInside), for: .touchUpInside)
        addTarget(self, action: #selector(touchEnded), for: [.touchUpOutside, .touchCancel])
    }

    @objc private func touchDown() {
        onTouchDown?()
        holdTriggered = false
        repeatTriggered = false
        holdTimer?.invalidate()
        repeatDelayTimer?.invalidate()
        repeatTimer?.invalidate()
        if onHold != nil {
            holdTimer = scheduleTimer(interval: holdThreshold, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.holdTriggered = true
                self.onHold?()
            }
        }

        if onRepeatTick != nil {
            repeatDelayTimer = self.scheduleTimer(interval: repeatInitialDelay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.repeatTriggered = true
                self.onRepeatTick?()
                self.repeatTimer = self.scheduleTimer(interval: self.repeatInterval, repeats: true) { [weak self] _ in
                    self?.onRepeatTick?()
                }
            }
        }
    }

    @objc private func touchUpInside() {
        holdTimer?.invalidate()
        repeatDelayTimer?.invalidate()
        repeatTimer?.invalidate()
        holdTimer = nil
        repeatDelayTimer = nil
        repeatTimer = nil
        defer {
            holdTriggered = false
            repeatTriggered = false
            onTouchRelease?()
        }
        guard !holdTriggered, !repeatTriggered else { return }
        onTap?()
    }

    @objc private func touchEnded() {
        holdTimer?.invalidate()
        repeatDelayTimer?.invalidate()
        repeatTimer?.invalidate()
        holdTimer = nil
        repeatDelayTimer = nil
        repeatTimer = nil
        holdTriggered = false
        repeatTriggered = false
        onTouchRelease?()
    }
}

/// Small floating tooltip shown when holding down a button for alternate action
private class HoldTooltip: UIView {

    init(text: String) {
        super.init(frame: .zero)

        backgroundColor = .systemBackground
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Arrow Nipple View

class ArrowNippleView: UIView {

    enum Direction {
        case up, down, left, right
    }

    var onArrowInput: ((Direction) -> Void)?
    var onDoubleTap: (() -> Void)?

    private let nipple = UIView()
    private var repeatTimer: Timer?
    private var repeatDelayTimer: Timer?
    private var currentDirection: Direction?
    private var currentMagnitude: CGFloat = 0
    private var hasSentInitialInput = false

    /// Minimum threshold before any arrow is triggered (in points)
    private let activationThreshold: CGFloat = 20.0

    /// Maximum drag distance for fastest repeat (in points)
    private let maxDragDistance: CGFloat = 50.0

    /// Delay before repeat starts (to distinguish flick from hold)
    private let repeatDelay: TimeInterval = 0.3

    /// Slowest repeat interval (at activation threshold)
    private let slowestRepeat: TimeInterval = 0.2

    /// Fastest repeat interval (at max drag)
    private let fastestRepeat: TimeInterval = 0.04

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // More visible background
        backgroundColor = .secondarySystemFill
        layer.cornerRadius = 8

        // Center nipple - more visible
        nipple.backgroundColor = .secondaryLabel
        nipple.layer.cornerRadius = 8
        nipple.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nipple)

        NSLayoutConstraint.activate([
            nipple.centerXAnchor.constraint(equalTo: centerXAnchor),
            nipple.centerYAnchor.constraint(equalTo: centerYAnchor),
            nipple.widthAnchor.constraint(equalToConstant: 16),
            nipple.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Pan gesture for arrow input
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        // Double tap opens full session selector
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)

        panGesture.require(toFail: doubleTapGesture)
    }

    @objc private func handleDoubleTap() {
        onDoubleTap?()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            let translation = gesture.translation(in: self)

            // Calculate magnitude of drag
            let absX = abs(translation.x)
            let absY = abs(translation.y)
            let magnitude = max(absX, absY)

            // Animate nipple offset (always, even below threshold)
            let maxOffset: CGFloat = 8
            let offsetX = min(max(translation.x, -maxOffset), maxOffset)
            let offsetY = min(max(translation.y, -maxOffset), maxOffset)
            nipple.transform = CGAffineTransform(translationX: offsetX, y: offsetY)

            // Only activate if past threshold
            guard magnitude > activationThreshold else {
                // Below threshold - cancel any pending repeat
                if currentDirection != nil {
                    stopRepeat()
                    currentDirection = nil
                    hasSentInitialInput = false
                }
                return
            }

            // Determine direction based on which axis has greater magnitude
            let newDirection: Direction
            if absX > absY {
                newDirection = translation.x > 0 ? .right : .left
            } else {
                newDirection = translation.y > 0 ? .down : .up
            }

            // Update magnitude for repeat speed calculation
            currentMagnitude = magnitude

            // If direction changed or first activation
            if currentDirection != newDirection {
                stopRepeat()
                currentDirection = newDirection
                hasSentInitialInput = false
            }

            // Send initial input once when direction is first set
            if !hasSentInitialInput {
                hasSentInitialInput = true
                onArrowInput?(newDirection)
                // Start delay timer - repeat only starts after holding
                startRepeatDelay()
            }

        case .ended, .cancelled:
            stopRepeat()
            currentDirection = nil
            currentMagnitude = 0
            hasSentInitialInput = false

            // Animate nipple back to center
            UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
                self.nipple.transform = .identity
            }

        default:
            break
        }
    }

    /// Calculate repeat interval based on drag magnitude (further = faster)
    private func repeatInterval() -> TimeInterval {
        // Normalize magnitude to 0-1 range (activation threshold to max)
        let normalizedMagnitude = min(
            (currentMagnitude - activationThreshold) / (maxDragDistance - activationThreshold),
            1.0
        )
        // Interpolate between slowest and fastest
        return slowestRepeat - (normalizedMagnitude * (slowestRepeat - fastestRepeat))
    }

    private func startRepeatDelay() {
        repeatDelayTimer?.invalidate()
        repeatDelayTimer = Timer.scheduledTimer(withTimeInterval: repeatDelay, repeats: false) { [weak self] _ in
            // After delay, start repeating if still holding
            self?.startRepeat()
        }
    }

    private func startRepeat() {
        repeatTimer?.invalidate()
        scheduleNextRepeat()
    }

    private func scheduleNextRepeat() {
        guard currentDirection != nil else { return }
        let interval = repeatInterval()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, let dir = self.currentDirection else { return }
            self.onArrowInput?(dir)
            self.scheduleNextRepeat()  // Schedule next with potentially new interval
        }
    }

    private func stopRepeat() {
        repeatDelayTimer?.invalidate()
        repeatDelayTimer = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

// MARK: - Circular Progress View

/// Simple linear progress bar for download indication
private class CircularProgressView: UIView {

    var progress: CGFloat = 0 {
        didSet {
            setNeedsLayout()
        }
    }

    private let trackLayer = CALayer()
    private let progressLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Track (background)
        trackLayer.backgroundColor = UIColor.secondarySystemFill.cgColor
        layer.addSublayer(trackLayer)

        // Progress fill
        progressLayer.backgroundColor = UIColor.systemBlue.cgColor
        layer.addSublayer(progressLayer)

        // Rounded corners
        layer.cornerRadius = 2
        clipsToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2

        let progressWidth = bounds.width * min(max(progress, 0), 1)
        progressLayer.frame = CGRect(x: 0, y: 0, width: progressWidth, height: bounds.height)
        progressLayer.cornerRadius = bounds.height / 2
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        trackLayer.backgroundColor = UIColor.secondarySystemFill.cgColor
        progressLayer.backgroundColor = UIColor.systemBlue.cgColor
    }
}
