import SwiftUI
import UIKit

final class IceVaultAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        IceVaultOrientation.current
    }
}

@main
struct IceVaultSlotApp: App {
    @UIApplicationDelegateAdaptor(IceVaultAppDelegate.self) private var appDelegate
    @StateObject private var store = IceVaultStore()

    var body: some Scene {
        WindowGroup {
            IceVaultArrivalStage()
                .environmentObject(store)
        }
    }
}
