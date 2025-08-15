import Cocoa
import AppKit

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private let menu = NSMenu()
    private var updateTimer: Timer?
    private var iconTimer: Timer?
    private var menuUpdateTimer: Timer?
    var iconAnimate: Int = 0
    var signalLevel: SignalStrengthLevel = .none
    var state: PPPConnectionState = .disconnected
    
    // Menu items references for live updates
    private var dataUsageMenuItem: NSMenuItem?
    private var connectionTimeMenuItem: NSMenuItem?
    private var signalMenuItem: NSMenuItem?
    private var operatorMenuItem: NSMenuItem?
    private var cellularToggleSwitch: NSSwitch?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        
        // Nastavit delegate pro menu
        menu.delegate = self
        
        constructMenu()
        updateStatusIcon()

        // Spuštění periodické kontroly
        startStatusUpdates()
    }
    
    func makeOperatorMenuItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        
        // Create circular icon for cellular (28px)
        let iconView = NSView(frame: NSRect(x: 10, y: 2, width: 28, height: 28))
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 14
        iconView.layer?.backgroundColor = PPPManager.shared.connectionState() == .connected ? NSColor.systemBlue.cgColor :  NSColor.systemGray.cgColor
        
        // Add cellular icon from Assets
        let cellularImageView = NSImageView(frame: NSRect(x: 6, y: 6, width: 16, height: 16))
        cellularImageView.image = NSImage(named: "Signal4")
        cellularImageView.imageScaling = .scaleProportionallyUpOrDown
        iconView.addSubview(cellularImageView)
        
        // Operator name label
        let operatorLabel = NSTextField(labelWithString: (PPPManager.shared.connectionState() == .connected ? ModemManager.shared.operatorName : Settings.shared.operatorNAME) ?? NSLocalizedString("Unknown", comment: "unknown"))
        operatorLabel.font = NSFont.systemFont(ofSize: 13)
        operatorLabel.frame = NSRect(x: 48, y: 8, width: 150, height: 16)
        operatorLabel.textColor = NSColor.labelColor
        operatorLabel.backgroundColor = NSColor.clear
        operatorLabel.isBordered = false
        operatorLabel.isEditable = false
        
        container.addSubview(iconView)
        container.addSubview(operatorLabel)
        
        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        
        // Store reference to the label for updates
        item.representedObject = operatorLabel
        
        return item
    }
    
    func constructMenu() {
        menu.removeAllItems()
        
        if !ModemManager.shared.disUpdates {
            state = PPPManager.shared.connectionState()
        }
        
        // Cellular data toggle
        let dataSwitch = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))

        let label = NSTextField(labelWithString: NSLocalizedString("Celluar data", comment: "Celluar data"))
        label.font = .boldSystemFont(ofSize: 13)
        label.frame = NSRect(x: 10, y: 8, width: 120, height: 16)

        let toggle = NSSwitch(frame: NSRect(x: 150, y: 4, width: 40, height: 20))
        toggle.state = state != .disconnected ? .on : .off
        toggle.target = self
        toggle.action = #selector(togglePPP(_:))
        
        // Store reference for updates
        cellularToggleSwitch = toggle

        container.addSubview(label)
        container.addSubview(toggle)

        dataSwitch.view = container
        menu.addItem(dataSwitch)
        
        menu.addItem(NSMenuItem.separator())
        
        // Network section and operator item - only visible when connecting or connected
        if state == .connected || state == .connecting {
            // Network section label
            let networkLabel = NSMenuItem(title: "Síť", action: nil, keyEquivalent: "")
            networkLabel.attributedTitle = NSAttributedString(string: "Síť", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ])
            networkLabel.isEnabled = false
            menu.addItem(networkLabel)
            
            // Operator item with icon (keep original design)
            operatorMenuItem = makeOperatorMenuItem()
            menu.addItem(operatorMenuItem!)
            
            // Info submenu for connection details (only when connected)
            if state == .connected && !ModemManager.shared.disUpdates {
                let infoItem = NSMenuItem(title: "Info", action: nil, keyEquivalent: "")
                let infoSubmenu = NSMenu(title: "Info")
                
                // Signal strength
                if let signal = ModemManager.shared.getSignalStrength() {
                    self.signalLevel = signal.level
                    
                    var signalLine = NSLocalizedString("Signal", comment: "signal status")
                    signalLine += ": "
                    signalLine += "\(ModemManager.shared._rssi)/31"
                    signalMenuItem = NSMenuItem(title: signalLine, action: nil, keyEquivalent: "")
                    infoSubmenu.addItem(signalMenuItem!)
                }
                
                // Connection statistics
                dataUsageMenuItem = NSMenuItem(title: PPPManager.shared.getFormattedDataUsage(), action: nil, keyEquivalent: "")
                infoSubmenu.addItem(dataUsageMenuItem!)
                
                let connectionTime = PPPManager.shared.getFormattedConnectionTime()
                let timeLabel = NSLocalizedString("Connected", comment: "connection time") + ": \(connectionTime)"
                connectionTimeMenuItem = NSMenuItem(title: timeLabel, action: nil, keyEquivalent: "")
                infoSubmenu.addItem(connectionTimeMenuItem!)
                
                infoItem.submenu = infoSubmenu
                menu.addItem(infoItem)
            }
        } else {
            // Reset references when not connected
            operatorMenuItem = nil
            dataUsageMenuItem = nil
            connectionTimeMenuItem = nil
            signalMenuItem = nil
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
            let newState = PPPManager.shared.connectionState()
            
            // Check if connection state changed - if so, rebuild menu
            if self.state != newState {
                self.state = newState
                self.constructMenu()
                return
            }
            
            if self.state == .connected && ModemManager.shared.operatorName == "" {
                ModemManager.shared.updateOperatorName()
            }
            
            // Update menu content if menu is open
            if self.menuUpdateTimer != nil {
                self.updateMenuContent()
            }
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
            .foregroundColor: dark ? NSColor.white : NSColor.black
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        button.attributedTitle = attributedTitle
    }
    
    // MARK: - NSMenuDelegate methods
    
    func menuWillOpen(_ menu: NSMenu) {
        // Start continuous updates
        startMenuUpdateTimer()
    }
    
    func menuDidClose(_ menu: NSMenu) {
        // Stop timer when menu closes
        stopMenuUpdateTimer()
    }
    
    private func startMenuUpdateTimer() {
        stopMenuUpdateTimer()
        
        // Immediate update
        updateMenuContent()
        
        // Continuous updates every 0.5 seconds for smoother experience
        menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                self.updateMenuContent()
            }
        }
    }
    
    private func stopMenuUpdateTimer() {
        menuUpdateTimer?.invalidate()
        menuUpdateTimer = nil
    }
    
    private func updateMenuContent() {
        // Update cellular toggle state
        if let toggle = cellularToggleSwitch {
            let currentState = PPPManager.shared.connectionState()
            toggle.state = currentState != .disconnected ? .on : .off
        }
        
        // Update operator name
        if let operatorItem = operatorMenuItem,
           let operatorLabel = operatorItem.representedObject as? NSTextField {
            let newOperatorName = ModemManager.shared.operatorName ?? NSLocalizedString("Unknown", comment: "unknown")
            if operatorLabel.stringValue != newOperatorName {
                operatorLabel.stringValue = newOperatorName
            }
        }
        
        // Update signal strength
        if let signalItem = signalMenuItem, let signal = ModemManager.shared.getSignalStrength() {
            self.signalLevel = signal.level
            var signalLine = NSLocalizedString("Signal", comment: "signal status")
            signalLine += ": "
            signalLine += "\(ModemManager.shared._rssi)/31"
            signalItem.title = signalLine
        }
        
        // Update data usage
        if let dataItem = dataUsageMenuItem {
            dataItem.title = PPPManager.shared.getFormattedDataUsage()
        }
        
        // Update connection time
        if let connectionTimeItem = connectionTimeMenuItem {
            let connectionTime = PPPManager.shared.getFormattedConnectionTime()
            let timeLabel = NSLocalizedString("Connected", comment: "connection time") + ": \(connectionTime)"
            connectionTimeItem.title = timeLabel
        }
    }
}
