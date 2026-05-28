import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

/// A premium, highly original biometric disk console.
/// Designed specifically around the semantics of mounting an encrypted virtual disk.
/// Draws a minimalist blueprint of a virtual disk slot at the top, and a dedicated,
/// high-precision biometric scan pad at the bottom to host the fingerprint.
final class BiometricDiskConsoleView: NSView {
    private let outlineLayer = CAShapeLayer()
    private let slotLayer = CAShapeLayer()
    private let scanPadLayer = CAShapeLayer()
    private let glowLayer = CAGradientLayer()
    private let scanPadContainer = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupConsole()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupConsole() {
        // 1. Subtle, high-end radial background glow centered on the biometric scanner
        glowLayer.type = .radial
        glowLayer.colors = [
            NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor,
            NSColor.clear.cgColor
        ]
        glowLayer.locations = [0.0, 1.0]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.3)
        glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer?.addSublayer(glowLayer)

        // 2. Blueprint outline of the secure console chassis
        outlineLayer.fillColor = NSColor.clear.cgColor
        outlineLayer.strokeColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
        outlineLayer.lineWidth = 1.0
        layer?.addSublayer(outlineLayer)

        // 3. Virtual storage disk slot at the top (semantically representing the virtual drive)
        slotLayer.fillColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        slotLayer.strokeColor = NSColor.labelColor.withAlphaComponent(0.25).cgColor
        slotLayer.lineWidth = 1.5
        layer?.addSublayer(slotLayer)

        // 4. Biometric scan pad frame at the bottom (with highly visible corner ticks in dark mode)
        scanPadLayer.fillColor = NSColor.clear.cgColor
        scanPadLayer.strokeColor = NSColor.labelColor.withAlphaComponent(0.3).cgColor
        scanPadLayer.lineWidth = 1.2
        layer?.addSublayer(scanPadLayer)

        // 5. Container to hold and center the real LAAuthenticationView
        scanPadContainer.wantsLayer = true
        scanPadContainer.layer?.masksToBounds = false
        addSubview(scanPadContainer)
    }

    override func layout() {
        super.layout()
        
        let w = bounds.width
        let h = bounds.height
        
        glowLayer.frame = bounds
        
        // Console chassis outline path
        let outlinePath = CGMutablePath()
        outlinePath.addRoundedRect(
            in: bounds.insetBy(dx: 4, dy: 4),
            cornerWidth: 16,
            cornerHeight: 16
        )
        outlineLayer.path = outlinePath

        // Disk drive slot blueprint at the top (Y: 96 to 104)
        let slotWidth: CGFloat = 64
        let slotHeight: CGFloat = 8
        let slotRect = CGRect(
            x: (w - slotWidth) / 2,
            y: h - 36,
            width: slotWidth,
            height: slotHeight
        )
        let slotPath = CGMutablePath()
        slotPath.addRoundedRect(in: slotRect, cornerWidth: 4, cornerHeight: 4)
        slotLayer.path = slotPath

        // Biometric scan pad frame in the bottom half (Y: 24 to 80)
        let padSize: CGFloat = 56
        let padRect = CGRect(
            x: (w - padSize) / 2,
            y: 24,
            width: padSize,
            height: padSize
        )
        
        // Draw elegant high-tech corner crosshair ticks around the scan pad
        let padPath = CGMutablePath()
        let tickLen: CGFloat = 8
        
        // Top-Left corner ticks
        padPath.move(to: CGPoint(x: padRect.minX, y: padRect.maxY - tickLen))
        padPath.addLine(to: CGPoint(x: padRect.minX, y: padRect.maxY))
        padPath.addLine(to: CGPoint(x: padRect.minX + tickLen, y: padRect.maxY))
        
        // Top-Right corner ticks
        padPath.move(to: CGPoint(x: padRect.maxX - tickLen, y: padRect.maxY))
        padPath.addLine(to: CGPoint(x: padRect.maxX, y: padRect.maxY))
        padPath.addLine(to: CGPoint(x: padRect.maxX, y: padRect.maxY - tickLen))
        
        // Bottom-Right corner ticks
        padPath.move(to: CGPoint(x: padRect.maxX, y: padRect.minY + tickLen))
        padPath.addLine(to: CGPoint(x: padRect.maxX, y: padRect.minY))
        padPath.addLine(to: CGPoint(x: padRect.maxX - tickLen, y: padRect.minY))
        
        // Bottom-Left corner ticks
        padPath.move(to: CGPoint(x: padRect.minX + tickLen, y: padRect.minY))
        padPath.addLine(to: CGPoint(x: padRect.minX, y: padRect.minY))
        padPath.addLine(to: CGPoint(x: padRect.minX, y: padRect.minY + tickLen))
        
        scanPadLayer.path = padPath

        // Frame the real subview container perfectly inside the scan pad
        scanPadContainer.frame = padRect
    }

    func embedBiometricView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        scanPadContainer.addSubview(view)
        
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: scanPadContainer.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: scanPadContainer.centerYAnchor)
        ])
        
        // Let CoreAnimation scale the out-of-process remote view centered perfectly
        // We translate the scale origin to the 64x64 view's center (32, 32), scale, and translate back.
        // This avoids touching anchorPoint/position, preventing any layout position shifts in AppKit.
        view.wantsLayer = true
        let scale = 36.0 / 64.0
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, 32, 32, 0)
        transform = CATransform3DScale(transform, scale, scale, 1.0)
        transform = CATransform3DTranslate(transform, -32, -32, 0)
        view.layer?.transform = transform
    }
    
    override func updateLayer() {
        super.updateLayer()
        // Ensure dynamic colors re-evaluate when system appearance changes
        outlineLayer.strokeColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
        scanPadLayer.strokeColor = NSColor.labelColor.withAlphaComponent(0.3).cgColor
        slotLayer.fillColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        slotLayer.strokeColor = NSColor.labelColor.withAlphaComponent(0.25).cgColor
        glowLayer.colors = [
            NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor,
            NSColor.clear.cgColor
        ]
    }
}

/// A premium, interactive link-style button that handles the pointing hand cursor natively
/// and renders its text directly to avoid buggy AppKit HUD button cell color overrides.
final class InteractiveLinkButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override var intrinsicContentSize: NSSize {
        return attributedTitle.size()
    }

    override func draw(_ dirtyRect: NSRect) {
        let title = attributedTitle
        let titleSize = title.size()
        let rect = NSRect(
            x: (bounds.width - titleSize.width) / 2,
            y: (bounds.height - titleSize.height) / 2,
            width: titleSize.width,
            height: titleSize.height
        )
        title.draw(in: rect)
    }
}

@MainActor
final class LockOverlayView: NSView {
    var onUnlock: ((LAContext) -> Void)?

    private var laContext = LAContext()
    private var laView: LAAuthenticationView?
    private var activeFallbackContext: LAContext?
    private var consoleView: BiometricDiskConsoleView?
    private var isBiometricsInitialized = false

    private let containerStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let errorContainer = NSView()
    private let errorTitleLabel = NSTextField(labelWithString: "Decryption Error")
    private let errorDetailsLabel = NSTextField()

    private var loadingTimer: Timer?
    private var windowBecomeObserver: NSObjectProtocol?
    private var windowResignObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var appResignObserver: NSObjectProtocol?
    private var lastRefreshTime = Date.distantPast

    deinit {
        NSLog("[LockOverlay] deinit - invalidating active contexts and observers")
        laContext.invalidate()
        activeFallbackContext?.invalidate()
        if let obs = windowBecomeObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = windowResignObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = appActiveObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = appResignObserver { NotificationCenter.default.removeObserver(obs) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            NSLog("[LockOverlay] viewWillMoveToWindow(nil) - invalidating active contexts")
            laContext.invalidate()
            activeFallbackContext?.invalidate()
        }
    }

    init(frame frameRect: NSRect, serviceName: String, onUnlock: @escaping (LAContext) -> Void) {
        self.onUnlock = onUnlock
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        setupUI(serviceName: serviceName)
        registerFocusObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(serviceName: String) {
        wantsLayer = true
        layer?.cornerRadius = Constants.WINDOW_CORNER_RADIUS
        layer?.masksToBounds = true

        // Blurred glass backdrop
        let visualEffectView = NSVisualEffectView(frame: bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        addSubview(visualEffectView)

        // Center container
        containerStack.orientation = .vertical
        containerStack.spacing = 20
        containerStack.alignment = .centerX
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(containerStack)

        NSLayoutConstraint.activate([
            containerStack.centerXAnchor.constraint(equalTo: visualEffectView.centerXAnchor),
            containerStack.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            containerStack.widthAnchor.constraint(
                equalTo: visualEffectView.widthAnchor, multiplier: 0.8),
        ])
        // Semantically aligned biometric disk console
        let consoleView = BiometricDiskConsoleView()
        consoleView.translatesAutoresizingMaskIntoConstraints = false
        containerStack.addArrangedSubview(consoleView)
        self.consoleView = consoleView

        NSLayoutConstraint.activate([
            consoleView.widthAnchor.constraint(equalToConstant: 120),
            consoleView.heightAnchor.constraint(equalToConstant: 140)
        ])

        // Title
        let titleLabel = NSTextField(labelWithString: "Secure Storage Locked")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        containerStack.addArrangedSubview(titleLabel)

        // Subtitle (Original typographic styling)
        let userName = NSFullUserName().isEmpty ? "User" : NSFullUserName()
        let subtitleLabel = NSTextField(
            labelWithString:
                "Touch ID or enter password for \u{201C}\(userName)\u{201D}\nto unlock secure storage."
        )
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.cell?.wraps = true
        subtitleLabel.cell?.isScrollable = false
        containerStack.addArrangedSubview(subtitleLabel)

        // Premium "Use Password..." link button
        let passwordButton = InteractiveLinkButton()
        passwordButton.isBordered = false
        passwordButton.target = self
        passwordButton.action = #selector(usePasswordClicked)
        passwordButton.translatesAutoresizingMaskIntoConstraints = false
        
        let linkColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil {
                return NSColor(calibratedRed: 0.35, green: 0.65, blue: 1.0, alpha: 1.0)
            } else {
                return NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.9, alpha: 1.0)
            }
        }
        
        let buttonTitle = "Use Password..."
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: linkColor,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        passwordButton.attributedTitle = NSAttributedString(string: buttonTitle, attributes: attributes)
        
        containerStack.addArrangedSubview(passwordButton)

        // Progress indicator (hidden until mounting starts)
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isHidden = true
        containerStack.addArrangedSubview(progressIndicator)

        // Status label
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.cell?.wraps = true
        statusLabel.cell?.isScrollable = false
        statusLabel.isHidden = true
        containerStack.addArrangedSubview(statusLabel)

        // Error container
        errorContainer.wantsLayer = true
        errorContainer.layer?.cornerRadius = 8
        errorContainer.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        errorContainer.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.18).cgColor
        errorContainer.layer?.borderWidth = 1
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.isHidden = true
        containerStack.addArrangedSubview(errorContainer)

        let errorStack = NSStackView()
        errorStack.orientation = .vertical
        errorStack.spacing = 6
        errorStack.alignment = .leading
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.addSubview(errorStack)

        NSLayoutConstraint.activate([
            errorContainer.widthAnchor.constraint(equalTo: containerStack.widthAnchor),
            errorStack.leadingAnchor.constraint(
                equalTo: errorContainer.leadingAnchor, constant: 12),
            errorStack.trailingAnchor.constraint(
                equalTo: errorContainer.trailingAnchor, constant: -12),
            errorStack.topAnchor.constraint(equalTo: errorContainer.topAnchor, constant: 12),
            errorStack.bottomAnchor.constraint(
                equalTo: errorContainer.bottomAnchor, constant: -12),
        ])

        errorTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        errorTitleLabel.textColor = .systemRed
        errorTitleLabel.alignment = .left
        errorTitleLabel.cell?.wraps = true
        errorTitleLabel.cell?.isScrollable = false
        errorStack.addArrangedSubview(errorTitleLabel)

        errorDetailsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        errorDetailsLabel.textColor = .labelColor
        errorDetailsLabel.alignment = .left
        errorDetailsLabel.isSelectable = true
        errorDetailsLabel.isEditable = false
        errorDetailsLabel.drawsBackground = false
        errorDetailsLabel.isBezeled = false
        errorDetailsLabel.cell?.wraps = true
        errorDetailsLabel.cell?.isScrollable = false
        errorStack.addArrangedSubview(errorDetailsLabel)
    }

    override func mouseDown(with event: NSEvent) {
        // Block clicks from reaching the webview behind the overlay
    }

    func startLoading() {
        statusLabel.stringValue = "Preparing..."
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true
        progressIndicator.isHidden = true
        errorContainer.isHidden = true

        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) {
            [weak self] _ in
            guard let self = self else { return }
            self.progressIndicator.isHidden = false
            self.progressIndicator.startAnimation(nil)
            self.statusLabel.isHidden = false
        }
    }

    func updateStatus(_ status: String) {
        statusLabel.stringValue = status
    }

    func stopLoading() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        statusLabel.isHidden = true
    }

    func showError(_ error: String) {
        stopLoading()
        errorDetailsLabel.stringValue = error
        errorContainer.isHidden = false
    }

    @objc private func usePasswordClicked() {
        NSLog("[LockOverlay] usePasswordClicked fired - spawning dedicated fallback context")
        let fallbackContext = LAContext()
        self.activeFallbackContext = fallbackContext
        
        Task {
            do {
                try await fallbackContext.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Authorize access to secure engine local storage"
                )
                self.activeFallbackContext = nil
                onUnlock?(fallbackContext)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                }
            } catch {
                self.activeFallbackContext = nil
                NSLog("[LockOverlay] Fallback password authentication failed: %@", error.localizedDescription)
                let errString = error.localizedDescription
                if errString.contains("Canceled") || errString.contains("cancel") || errString.contains("-128") || errString.contains("denied") {
                    stopLoading()
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                    }
                    return
                }
                showError(error.localizedDescription)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    @objc private func unlockClicked() {
        NSLog(
            "[LockOverlay] unlockClicked fired, onUnlock is \(onUnlock == nil ? "nil" : "set")")

        Task {
            do {
                try await laContext.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Authorize access to secure engine local storage"
                )
                onUnlock?(laContext)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                }
            } catch {
                NSLog(
                    "[LockOverlay] LAContext evaluation failed: %@", error.localizedDescription)
                let errString = error.localizedDescription
                if errString.contains("Canceled") || errString.contains("cancel") || errString.contains("-128") || errString.contains("denied") {
                    stopLoading()
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                    }
                    return
                }
                showError(error.localizedDescription)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Re-create a fresh LAContext since the previous one was permanently invalidated on remove
            self.laContext = LAContext()
            self.isBiometricsInitialized = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self = self, let win = self.window else { return }
                
                // Only auto-acquire biometric focus if our window is actually key and application is active
                guard win.isKeyWindow, NSApp.isActive else {
                    NSLog("[LockOverlay] viewDidMoveToWindow - window is not key or app inactive, postponing biometrics")
                    return
                }
                
                if !self.isBiometricsInitialized, let console = self.consoleView {
                    self.isBiometricsInitialized = true
                    
                    NSLog("[LockOverlay] Initializing fresh LAAuthenticationView after delay")
                    
                    // Remove any existing laView first to prevent duplication or layout issues
                    self.laView?.removeFromSuperview()
                    
                    // Pure, completely uncustomized LAAuthenticationView with the fresh context
                    let laView = LAAuthenticationView(context: self.laContext)
                    self.laView = laView
                    
                    // Embed the fingerprint beautifully into the dedicated console scan pad
                    console.embedBiometricView(laView)
                }
                
                if self.errorContainer.isHidden {
                    self.unlockClicked()
                }
            }
        }
    }
    
    private func registerFocusObservers() {
        // Observe window becoming key
        windowBecomeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let win = notification.object as? NSWindow, win == self.window else { return }
            Task { @MainActor in
                self.refreshBiometricsIfNeeded()
            }
        }

        // Observe window resigning key
        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let win = notification.object as? NSWindow, win == self.window else { return }
            Task { @MainActor in
                self.releaseBiometrics()
            }
        }
        
        // Observe app becoming active
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.window != nil else { return }
            Task { @MainActor in
                self.refreshBiometricsIfNeeded()
            }
        }

        // Observe app resigning active
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.window != nil else { return }
            Task { @MainActor in
                self.releaseBiometrics()
            }
        }
    }
    
    private func releaseBiometrics() {
        NSLog("[LockOverlay] Releasing biometrics to free system Touch ID focus")
        self.laContext.invalidate()
        self.laView?.removeFromSuperview()
        self.laView = nil
        self.isBiometricsInitialized = false
    }
    
    private func refreshBiometricsIfNeeded() {
        // Only refresh if we have a window, we are not displaying an error, and no active fallback is running.
        guard let win = window, errorContainer.isHidden, activeFallbackContext == nil else { return }
        
        // Also only refresh if we are currently active and key
        guard win.isKeyWindow, NSApp.isActive else { return }
        
        // Debounce if we are already initialized
        let now = Date()
        if isBiometricsInitialized {
            guard now.timeIntervalSince(lastRefreshTime) > 1.5 else { return }
        }
        
        lastRefreshTime = now
        
        NSLog("[LockOverlay] App/Window gained focus - initializing/refreshing biometrics")
        
        self.laContext.invalidate()
        self.laContext = LAContext()
        self.isBiometricsInitialized = true
        
        if let console = self.consoleView {
            self.laView?.removeFromSuperview()
            let laView = LAAuthenticationView(context: self.laContext)
            self.laView = laView
            console.embedBiometricView(laView)
        }
        
        self.unlockClicked()
    }
}
