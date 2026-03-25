import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Zruší hlavní app window – menubar-only aplikace
        NSApp.setActivationPolicy(.accessory)
        
        // Inicializace status baru
        statusBarController = StatusBarController()

        // ACPI modem initialization on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            ModemManager.shared.initializeModem()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        PPPManager.shared.disconnect()
    }
}
