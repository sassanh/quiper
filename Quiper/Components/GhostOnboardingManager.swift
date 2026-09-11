import AppKit
import Carbon

@MainActor
final class GhostOnboardingManager {
    static let shared = GhostOnboardingManager()
    
    private weak var windowController: MainWindowController?
    private var currentStep = 0
    
    var isActive: Bool {
        return currentStep > 0 && currentStep <= 3 && !Settings.shared.hasCompletedGhostOnboarding
    }
    
    private init() {}
    
    func start(in windowController: MainWindowController) {
        let isRunningTests = NSClassFromString("XCTestCase") != nil
        let shouldForceOnboarding = CommandLine.arguments.contains("--test-onboarding")
        
        guard (!isRunningTests && !Constants.LaunchMode.shouldSuppressInterferenceUI) || shouldForceOnboarding else {
            return
        }
        
        guard !Settings.shared.hasCompletedGhostOnboarding else {
            return
        }
        
        self.windowController = windowController
        let isResuming = self.currentStep > 0
        if self.currentStep == 0 {
            self.currentStep = 1
        }
        
        // Force the header to expand immediately during onboarding
        windowController.updateHeaderVisibility(animated: false)
        
        // Disable selector hover/click interactions during onboarding
        windowController.collapsibleServiceSelector?.isInteractionEnabled = false
        windowController.collapsibleSessionSelector?.isInteractionEnabled = false
        
        if isResuming {
            // Resuming after window regained focus — re-show the current step
            // to re-expand selectors and re-assert first responder
            showCurrentStep()
        } else {
            // First launch — wait a brief moment for the UI to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.showCurrentStep()
                }
            }
        }
    }
    
    func windowDidResignKey() {
        if isActive {
            // During onboarding, keep the HUD in place so the first click back
            // on the window can't reach underlying UI elements
            return
        }
        windowController?.hideOnboardingHUD()
    }
    
    func serviceDidSwitch() {
        if currentStep == 1 {
            currentStep = 2
            showCurrentStep()
        }
    }
    
    func sessionDidSwitch() {
        if currentStep == 2 {
            currentStep = 3
            showCurrentStep()
        }
    }
    
    func advanceFromMenuClick() {
        if currentStep == 3 {
            completeOnboarding()
        }
    }
    
    func advanceStep() {
        if currentStep == 1 {
            currentStep = 2
            showCurrentStep()
        } else if currentStep == 2 {
            currentStep = 3
            showCurrentStep()
        } else if currentStep == 3 {
            completeOnboarding()
        }
    }

    func retreatStep() {
        if currentStep == 3 {
            currentStep = 2
            showCurrentStep()
        } else if currentStep == 2 {
            currentStep = 1
            showCurrentStep()
        }
    }

    /// Single gate for tip navigation keys, shared by the event monitor and
    /// the HUD view. Returns whether the key navigated.
    @discardableResult
    func handleTipKey(keyCode: UInt16) -> Bool {
        switch keyCode {
        case UInt16(kVK_Return), UInt16(kVK_Space), UInt16(kVK_Escape), UInt16(kVK_RightArrow):
            advanceStep()
            return true
        case UInt16(kVK_LeftArrow), UInt16(kVK_Delete):
            retreatStep()
            return true
        default:
            return false
        }
    }
    
    private func showCurrentStep() {
        guard let wc = windowController, let window = wc.window, window.isVisible else {
            return
        }
        
        switch currentStep {
        case 1:
            wc.layoutSelectors()
            wc.collapsibleServiceSelector?.expand()
            wc.collapsibleServiceSelector?.expandedPanel?.ignoresMouseEvents = true
            wc.collapsibleSessionSelector?.collapse()
            
            if let target = wc.activeServiceSelector {
                wc.showOnboardingHUD(
                    step: 1,
                    title: "Switch AI Services",
                    text: "This is your service list. Use `⌃⌘1` to `⌃⌘9` to switch between AI services instantly.",
                    target: target
                )
            }
        case 2:
            wc.layoutSelectors()
            wc.collapsibleServiceSelector?.collapse()
            wc.collapsibleSessionSelector?.expand()
            wc.collapsibleSessionSelector?.expandedPanel?.ignoresMouseEvents = true
            
            if let target = wc.activeSessionSelector {
                wc.showOnboardingHUD(
                    step: 2,
                    title: "Independent Chat Slots",
                    text: "Each service has 10 isolated slots. Press `⌘1` to `⌘0` to switch between slots instantly.",
                    target: target
                )
            }
        case 3:
            wc.layoutSelectors()
            wc.collapsibleServiceSelector?.collapse()
            wc.collapsibleSessionSelector?.collapse()
            
            if let target = wc.sessionActionsButton {
                wc.showOnboardingHUD(
                    step: 3,
                    title: "Settings & Options",
                    text: "Press `⌘⇧,` to access Settings.\n\nDouble-tap `⌘` to toggle the Control Center.\n\nEnjoy using Quiper!",
                    target: target
                )
                // Auto dismiss step 3 after 10 seconds if not clicked
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                    Task { @MainActor [weak self] in
                        if self?.currentStep == 3 {
                            self?.completeOnboarding()
                        }
                    }
                }
            }
        default:
            completeOnboarding()
        }
    }
    
    func completeOnboarding() {
        guard currentStep <= 3 else { return }
        currentStep = 4
        Settings.shared.hasCompletedGhostOnboarding = true
        
        // Re-enable selector hover/click interactions
        windowController?.collapsibleServiceSelector?.isInteractionEnabled = true
        windowController?.collapsibleSessionSelector?.isInteractionEnabled = true
        
        windowController?.hideOnboardingHUD()
        windowController?.updateHeaderVisibility(animated: true)
    }
}

