import Cocoa
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private let menu = NSMenu()
    private var updateTimer: Timer?
    private var iconTimer: Timer?
    var iconAnimate: Int = 0
    var signalLevel: SignalStrengthLevel = .none
    var state: PPPConnectionState = .disconnected
    
    // MyMenu
    

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        constructMenu()
        updateStatusIcon()

        // Spuštění periodické kontroly
        startStatusUpdates()
    }
    
    func makeSignalMenuItem(signalLabel: String, percent: Int) -> NSMenuItem {
        let title = "\(signalLabel)"

        // Napadovaná procenta jako "badge"
        let fullString = NSMutableAttributedString(string: title)

        let percentString = String(format: "   %3d%%", percent) // pevná šířka
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let badge = NSAttributedString(string: percentString, attributes: attrs)

        fullString.append(badge)

        let item = NSMenuItem()
        item.attributedTitle = fullString
        item.isEnabled = false // nebo true, pokud má být interaktivní
        return item
    }
    
    func constructMenu() {
        menu.removeAllItems()
        
        
        if !ModemManager.shared.disUpdates {
            state = PPPManager.shared.connectionState()
        }
        
        /*let statusText: String

        switch state {
        case .connected:
            statusText = "Připojeno"
        case .connecting:
            statusText = "Připojuji..."
        case .disconnected:
            statusText = "Nepřipojeno"
        }*/

        
        let dataSwitch = NSMenuItem()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))

        let label = NSTextField(labelWithString: NSLocalizedString("Celluar data", comment: "Celluar data"))
        label.font = .boldSystemFont(ofSize: 13)
        
        label.frame = NSRect(x: 10, y: 8, width: 120, height: 16)

        let toggle = NSSwitch(frame: NSRect(x: 150, y: 4, width: 40, height: 20))
        toggle.state =  state != .disconnected ? .on : .off
        toggle.target = self
        toggle.action = #selector(togglePPP(_:))

        container.addSubview(label)
        container.addSubview(toggle)

        dataSwitch.view = container
        menu.addItem(dataSwitch)
        
        menu.addItem(NSMenuItem.separator())
        
        
        //menu.addItem(withTitle: "Stav: \(statusText)", action: nil, keyEquivalent: "")
        if state == .connected || state == .connecting {
            var operatorText = NSLocalizedString("Operator", comment: "operator")
            operatorText += ": "
            operatorText += ModemManager.shared.operatorName ?? NSLocalizedString("Unknown", comment: "unknown")
            menu.addItem(withTitle: operatorText, action: nil, keyEquivalent: "")
        }
        
        // 2. Síla signálu
        if state == .connected && !ModemManager.shared.disUpdates
        {
            if let signal = ModemManager.shared.getSignalStrength() {
                self.signalLevel = signal.level
                //let rssi = (Int(ModemManager.shared._rssi.) / 31) * 100
                
                //let signalItem = makeSignalMenuItem(signalLabel: "Signál: \(signal.level.rawValue)", percent: rssi)
                //menu.addItem(signalItem)
                
                var signalLine = NSLocalizedString("Signal", comment: "signal status")
                signalLine += ": "
                signalLine += "\(ModemManager.shared._rssi)/31"
                menu.addItem(withTitle: signalLine, action: nil, keyEquivalent: "")
            }
        }
        


        menu.addItem(NSMenuItem.separator())


        let aboutItem = NSMenuItem(title: NSLocalizedString("About modem", comment: "opens modem info"), action: #selector(showModemInfo), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        let settingsItem = NSMenuItem(title: NSLocalizedString("Settings", comment: "opens settings window"), action: #selector(openPreferences), keyEquivalent: "s")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: NSLocalizedString("Quit", comment: "quit app"), action: #selector(terminate), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        //updateStatusIcon()
    }
    
    @objc func togglePPP(_ sender: NSButton) {
        if sender.state == .on {
            if !PPPManager.shared.connect() {
                sender.state = .off
            }
        } else {
            PPPManager.shared.disconnect()
        }
    }

    @objc func toggleConnection() {

        let state = PPPManager.shared.connectionState()
        switch state {
        case .connecting:
            PPPManager.shared.disconnect()
        case .connected:
            PPPManager.shared.disconnect()
        case .disconnected:
            if PPPManager.shared.connect() {
                //
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.constructMenu()
        }
    }

    @objc func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
    }

    @objc func showModemInfo() {
        AboutModemWindowController.shared.showWindow(nil)
    }

    @objc func terminate() {
        NSApplication.shared.terminate(nil)
    }

    private func startStatusUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateStatus()
        }
        
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            self.updateStatusIcon()
        }
    }

    private func updateStatus() {
        DispatchQueue.main.async {
            if self.state == .connected && ModemManager.shared.operatorName == "" {
                ModemManager.shared.updateOperatorName()
            }
            
            self.constructMenu()
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let appearance = NSApp.effectiveAppearance
        let dark = (appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua && Settings.shared.iconColor == 0) || Settings.shared.iconColor == 1
        var title = ""
        switch state {
        case .connected:

            title = Settings.shared.showOperator ? (ModemManager.shared.operatorName ?? "") : ""
            
            if signalLevel == .poor {
                button.image = NSImage(imageLiteralResourceName: dark ? "Signal1" : "Signal1_")
            }else if signalLevel == .fair {
                button.image = NSImage(imageLiteralResourceName: dark ? "Signal2" : "Signal2_")
            }else if signalLevel == .good {
                button.image = NSImage(imageLiteralResourceName: dark ? "Signal3" : "Signal3_")
            }else if signalLevel == .excellent {
                button.image = NSImage(imageLiteralResourceName: dark ? "Signal4" : "Signal4_")
            }else{
                button.image = NSImage(imageLiteralResourceName: dark ? "Signal0" : "Signal0_")
            }
            
        case .disconnected:
            title = ""
            button.image = NSImage(imageLiteralResourceName: dark ? "Offline" : "Offline_")
            
        case .connecting:
            title = NSLocalizedString("Connecting...", comment: "connecting")
            if iconAnimate == 0 {
                button.image = NSImage(imageLiteralResourceName: dark ? "Connecting0" : "Connecting0_")
            }else if iconAnimate == 1 || iconAnimate == 5 {
                button.image = NSImage(imageLiteralResourceName: dark ? "Connecting1" : "Connecting1_")
            }else if iconAnimate == 2 || iconAnimate == 4 {
                button.image = NSImage(imageLiteralResourceName: dark ? "Connecting2" : "Connecting2_")
            }else if iconAnimate == 3 {
                button.image = NSImage(imageLiteralResourceName: dark ? "Connecting3" : "Connecting3_")
            }
            iconAnimate += 1
            
            if iconAnimate == 6 {
                iconAnimate = 0
            }
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: dark ? NSColor.white : NSColor.black // Replace with your desired color
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        button.attributedTitle = attributedTitle
    }
}
