import SwiftUI
import UIKit

@MainActor
enum IceVaultOrientation {
    static var current: UIInterfaceOrientationMask = .portrait {
        didSet {
            refreshSupportedInterfaceOrientations()
        }
    }

    private static func refreshSupportedInterfaceOrientations() {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        for scene in windowScenes {
            for window in scene.windows {
                updateSupportedInterfaceOrientations(from: window.rootViewController)
            }

            if #available(iOS 16.0, *) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: current))
            }
        }
    }

    private static func updateSupportedInterfaceOrientations(from viewController: UIViewController?) {
        viewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        if let navigationController = viewController as? UINavigationController {
            updateSupportedInterfaceOrientations(from: navigationController.visibleViewController)
        }

        if let tabBarController = viewController as? UITabBarController {
            updateSupportedInterfaceOrientations(from: tabBarController.selectedViewController)
        }

        if let presentedViewController = viewController?.presentedViewController {
            updateSupportedInterfaceOrientations(from: presentedViewController)
        }
    }
}
