// SPDX-License-Identifier: GPL-2.0-only

import SwiftUI

@main
struct ARMSX3App: App {
    @UIApplicationDelegateAdaptor(ARMSX3AppDelegate.self) private var appDelegate
    // Ps3p: the Install folder exists from first launch so it shows in the Files app.
    init() { Ps3pInstallInbox.prepare() }

    var body: some Scene {
        WindowGroup {
            ARMSX3FrontendRoot()
        }
        .backgroundTask(.urlSession(UpdateStore.sessionID)) { await UpdateStore.finishBackgroundEvents() }
    }
}
