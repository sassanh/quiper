import AppKit

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
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        let shouldForceOnboarding = CommandLine.arguments.contains("--test-onboarding")
        
        guard (!isRunningTests && !isUITesting) || shouldForceOnboarding else {
            NSLog("[GhostOnboardingManager] start ignored: running in test environment")
            return
        }
        
        guard !Settings.shared.hasCompletedGhostOnboarding else {
            NSLog("[GhostOnboardingManager] start ignored: onboarding already completed")
            return
        }
        
        self.windowController = windowController
        let isResuming = self.currentStep > 0
        if self.currentStep == 0 {
            self.currentStep = 1
        }
        
        NSLog("[GhostOnboardingManager] start/resume called: currentStep = %d, isResuming = %d", currentStep, isResuming ? 1 : 0)
        
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
            NSLog("[GhostOnboardingManager] window resigned key during onboarding, keeping HUD")
            return
        }
        NSLog("[GhostOnboardingManager] window resigned key, hiding onboarding HUD")
        windowController?.hideOnboardingHUD()
    }
    
    func serviceDidSwitch() {
        NSLog("[GhostOnboardingManager] serviceDidSwitch, currentStep = %d", currentStep)
        if currentStep == 1 {
            currentStep = 2
            showCurrentStep()
        }
    }
    
    func sessionDidSwitch() {
        NSLog("[GhostOnboardingManager] sessionDidSwitch, currentStep = %d", currentStep)
        if currentStep == 2 {
            currentStep = 3
            showCurrentStep()
        }
    }
    
    func advanceFromMenuClick() {
        NSLog("[GhostOnboardingManager] advanceFromMenuClick, currentStep = %d", currentStep)
        if currentStep == 3 {
            completeOnboarding()
        }
    }
    
    func advanceStep() {
        NSLog("[GhostOnboardingManager] advanceStep programmatically, currentStep = %d", currentStep)
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
    
    private func showCurrentStep() {
        guard let wc = windowController, let window = wc.window, window.isVisible else {
            NSLog("[GhostOnboardingManager] showCurrentStep cancelled: window not visible or controller nil")
            return
        }
        
        NSLog("[GhostOnboardingManager] showCurrentStep: step = %d", currentStep)
        
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
            } else {
                NSLog("[GhostOnboardingManager] Warning: activeServiceSelector is nil in step 1")
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
            } else {
                NSLog("[GhostOnboardingManager] Warning: activeSessionSelector is nil in step 2")
            }
        case 3:
            wc.layoutSelectors()
            wc.collapsibleServiceSelector?.collapse()
            wc.collapsibleSessionSelector?.collapse()
            
            if let target = wc.sessionActionsButton {
                wc.showOnboardingHUD(
                    step: 3,
                    title: "Settings & Options",
                    text: "Press `⌘,` to access Settings.\n\nDouble-tap `⌘` or press `⌘⎋` to toggle the Control Center.\n\nEnjoy using Quiper!",
                    target: target
                )
                // Auto dismiss step 3 after 10 seconds if not clicked
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                    Task { @MainActor [weak self] in
                        if self?.currentStep == 3 {
                            NSLog("[GhostOnboardingManager] Auto-dismissing step 3 after timeout")
                            self?.completeOnboarding()
                        }
                    }
                }
            } else {
                NSLog("[GhostOnboardingManager] Warning: sessionActionsButton is nil in step 3")
            }
        default:
            completeOnboarding()
        }
    }
    
    func completeOnboarding() {
        guard currentStep <= 3 else { return }
        NSLog("[GhostOnboardingManager] completeOnboarding: setting hasCompletedGhostOnboarding = true")
        currentStep = 4
        Settings.shared.hasCompletedGhostOnboarding = true
        
        // Re-enable selector hover/click interactions
        windowController?.collapsibleServiceSelector?.isInteractionEnabled = true
        windowController?.collapsibleSessionSelector?.isInteractionEnabled = true
        
        windowController?.hideOnboardingHUD()
        windowController?.updateHeaderVisibility(animated: true)
    }
}

