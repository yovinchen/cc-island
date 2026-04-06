import Foundation
import Mixpanel

enum MixpanelTracker {
    private static let token = "49814c1436104ed108f3fc4735228496"
    private static var isInitialized = false

    static func initializeIfNeeded() {
        guard !isInitialized else { return }
        Mixpanel.initialize(token: token)
        isInitialized = true
    }

    static func withInstance(_ action: (MixpanelInstance) -> Void) {
        guard isInitialized else { return }
        action(Mixpanel.mainInstance())
    }
}
