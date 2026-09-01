import SwiftUI

@main
struct KnurlRemoteApp: App {
    @State private var session = PhoneSession()

    var body: some Scene {
        WindowGroup {
            CrownView(session: session)
                .frame(minWidth: 390, minHeight: 720)
        }
        .defaultSize(width: 420, height: 780)
        .windowResizability(.contentMinSize)
    }
}
