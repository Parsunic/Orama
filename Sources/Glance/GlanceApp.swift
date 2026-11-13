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
            MenuBarIcon(volume: appDelegate.volume)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    let volume = VolumeMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces: Info.plist already hides the Dock icon, but this also
        // covers running the bare binary during development.
        NSApp.setActivationPolicy(.accessory)
        controller.start()
    }
}

/// The menu bar icon shows the Mac's current volume and nothing else. It never
/// reflects what Glance is doing (working, answers hidden), so it looks the same
/// in a screenshot or screen share whatever state Glance is in.
struct MenuBarIcon: View {
    @ObservedObject var volume: VolumeMonitor

    var body: some View {
        Image(systemName: volume.symbolName)
    }
}
