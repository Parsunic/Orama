import AppKit
import SwiftUI

/// The whole app lives in the menu bar: no Dock icon (LSUIElement in
/// Info.plist), no windows except the menu panel and the click-through overlays.
@main
struct GlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(controller: appDelegate.controller, settings: appDelegate.controller.settings)
        } label: {
            MenuBarIcon(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces: Info.plist already hides the Dock icon, but this also
        // covers running the bare binary during development.
        NSApp.setActivationPolicy(.accessory)
        controller.start()
    }
}

struct MenuBarIcon: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Image(systemName: controller.menuIconName)
    }
}
