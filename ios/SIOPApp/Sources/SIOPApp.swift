import SIOPKit
import SwiftUI

@main
struct SIOPApp: App {
    @StateObject private var session = AuthenticationSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                // Section 7.1: requests arrive at the `openid:` authorization endpoint.
                .onOpenURL { session.receive($0) }
        }
    }
}
