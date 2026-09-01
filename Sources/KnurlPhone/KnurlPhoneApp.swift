import SwiftUI

@main
struct KnurlPhoneApp: App {
    @State private var session = PhoneSession()

    var body: some Scene {
        WindowGroup {
            CrownView(session: session)
                .preferredColorScheme(.dark)
        }
    }
}
