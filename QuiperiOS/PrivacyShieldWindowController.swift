import UIKit

@MainActor
final class PrivacyShieldWindowController: NSObject {
    static let shared = PrivacyShieldWindowController()

    private var shieldWindows: [String: UIWindow] = [:]

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(show),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hide),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidDisconnect(_:)),
            name: UIScene.didDisconnectNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneWillDeactivate(_:)),
            name: UIScene.willDeactivateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidActivate(_:)),
            name: UIScene.didActivateNotification,
            object: nil
        )
    }

    @objc private func show() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            showShield(for: scene)
        }
    }

    @objc private func hide() {
        for window in shieldWindows.values {
            window.isHidden = true
            window.rootViewController = nil
        }
        shieldWindows.removeAll()
    }

    @objc private func sceneDidDisconnect(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        hideShield(for: scene)
    }

    @objc private func sceneWillDeactivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        showShield(for: scene)
    }

    @objc private func sceneDidActivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        hideShield(for: scene)
    }

    private func showShield(for scene: UIWindowScene) {
        let identifier = scene.session.persistentIdentifier
        guard shieldWindows[identifier] == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = PrivacyShieldViewController()
        window.isHidden = false
        shieldWindows[identifier] = window
    }

    private func hideShield(for scene: UIWindowScene) {
        let identifier = scene.session.persistentIdentifier
        guard let window = shieldWindows.removeValue(forKey: identifier) else { return }
        window.isHidden = true
        window.rootViewController = nil
    }
}

private final class PrivacyShieldViewController: UIViewController {
    override func loadView() {
        let container = UIView()
        container.backgroundColor = .systemBackground

        let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
        icon.tintColor = .tintColor
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Quiper"
        title.font = .preferredFont(forTextStyle: .title2).bold()
        title.textColor = .label
        title.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [icon, title])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "Quiper content hidden"
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 46),
            icon.heightAnchor.constraint(equalToConstant: 46),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        view = container
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
