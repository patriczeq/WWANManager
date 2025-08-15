import Cocoa

class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController(windowNibName: "PreferencesWindowController")
    var availableOperators: [(name: String, id: String)] = []
    //@IBOutlet weak var atPortField: NSTextField!
    //@IBOutlet weak var pppPortField: NSTextField!
    
    @IBOutlet weak var atPortPopup: NSPopUpButton!
    @IBOutlet weak var pppPortPopup: NSPopUpButton!
    @IBOutlet weak var testATPortButton: NSButton!
    @IBOutlet weak var testPPPPortButton: NSButton!
    @IBOutlet weak var apnField: NSTextField!
    @IBOutlet weak var pinField: NSTextField!
    @IBOutlet weak var baudField: NSTextField!
    @IBOutlet weak var passwdField: NSTextField!
    @IBOutlet weak var operatorPopup: NSPopUpButton!
    
    @IBOutlet weak var ipVerPopup: NSPopUpButton!
    @IBOutlet weak var customDNS: NSSwitch!
    @IBOutlet weak var primaryDNSField: NSTextField!
    @IBOutlet weak var secondaryDNSField: NSTextField!
    
    @IBOutlet weak var showOp: NSSwitch!
    
    // labels
    @IBOutlet weak var labelTitle: NSTextField!
    @IBOutlet weak var labelSubtitle: NSTextField!
    // tabs
    @IBOutlet weak var labelTabs: NSTabView!
    // operator
    @IBOutlet weak var labelOperator: NSTextField!
    @IBOutlet weak var labelSearch: NSButton!
    @IBOutlet weak var labelIPVer: NSTextField!
    // perso
    @IBOutlet weak var labelTopOperator: NSTextField!
    @IBOutlet weak var labelSavePassword: NSTextField!
    @IBOutlet weak var labelSavePasswordHint: NSTextField!
    @IBOutlet weak var labelIconColor: NSTextField!
    @IBOutlet weak var iconColor: NSPopUpButton!
    
    // save
    @IBOutlet weak var labelSave: NSButton!
    
    @IBOutlet weak var copyrightLabel: NSTextField!
    @IBOutlet weak var versionLabel: NSTextField!
    
    var LoadingOperators: Bool = false
    
    //@IBOutlet weak var showOp: NSButton!

    override func windowDidLoad() {
        super.windowDidLoad()
        // Aktivuj aplikaci a přines okno do popředí
        NSApp.activate(ignoringOtherApps: true)

        if let window = self.window {
            window.level = .floating         // Always on top
            window.center()                 // Doprostřed obrazovky
            window.makeKeyAndOrderFront(nil)
        }
        
        // add Titles
        labelTitle.stringValue = NSLocalizedString("Celluar data", comment: "Title of wwan manager")
        labelSubtitle.stringValue = NSLocalizedString("Setup your connection", comment: "subTitle of wwan manager")
        // tabs
        labelTabs.tabViewItems[0].label = NSLocalizedString("Interface", comment: "interface view")
        labelTabs.tabViewItems[1].label = NSLocalizedString("Network", comment: "network view")
        labelTabs.tabViewItems[2].label = NSLocalizedString("IP Conf", comment: "ip view")
        labelTabs.tabViewItems[3].label = NSLocalizedString("Personalization", comment: "pers view")
        // operator
        labelOperator.stringValue = NSLocalizedString("Operator", comment: "Operator selection")
        labelSearch.title = NSLocalizedString("Search", comment: "Search operators")
        labelIPVer.stringValue = NSLocalizedString("IP Ver.", comment: "IP version")
        // personal
        labelTopOperator.stringValue = NSLocalizedString("Show operator name in top bar", comment: "operator in menu bar")
        labelIconColor.stringValue = NSLocalizedString("Icon color", comment: "icon color")
        iconColor.removeAllItems()
        iconColor.addItem(withTitle: NSLocalizedString("Automatically", comment: "automatically"))
        iconColor.addItem(withTitle: NSLocalizedString("White", comment: "white"))
        iconColor.addItem(withTitle: NSLocalizedString("Black", comment: "black"))
        
        
        labelSavePasswordHint.stringValue = NSLocalizedString("You can save your password to avoid asking...", comment: "password hint")
        labelSavePassword.stringValue = NSLocalizedString("Save password", comment: "your account password")
        labelSave.title = NSLocalizedString("Save", comment: "Save settings")
        
        // Nastavení copyright a verze
        let infoDict = Bundle.main.infoDictionary
        
        copyrightLabel.stringValue = infoDict?["NSHumanReadableCopyright"] as? String ?? ""
        versionLabel.stringValue = "v\(infoDict?["CFBundleShortVersionString"] as? String ?? "Unknown")"
        
        loadSettings()
    }

    func loadSettings() {
        //atPortField.stringValue = Settings.shared.atPort
        //pppPortField.stringValue = Settings.shared.pppPort
        let ports = Settings.shared.availableSerialPorts()
            
        atPortPopup.removeAllItems()
        pppPortPopup.removeAllItems()

        atPortPopup.addItems(withTitles: ports)
        pppPortPopup.addItems(withTitles: ports)
        
        // Vybrat uloženou hodnotu, pokud existuje
        if Settings.shared.atPort != "" {
            atPortPopup.selectItem(withTitle: Settings.shared.atPort.replacingOccurrences(of: "/dev/", with: ""))
        }
        if Settings.shared.pppPort != "" {
            pppPortPopup.selectItem(withTitle: Settings.shared.pppPort.replacingOccurrences(of: "/dev/", with: ""))
        }
        apnField.stringValue = Settings.shared.apn
        pinField.stringValue = Settings.shared.pin
        baudField.stringValue = Settings.shared.baudrate
        passwdField.stringValue = Settings.shared.passwd
        
        
        showOp.state = Settings.shared.showOperator ? .on : .off
        
        
        availableOperators.removeAll()
        if Settings.shared.operatorID != "0" {
            availableOperators.append((NSLocalizedString("Automatically", comment: "auto"), "0"))
        }
        availableOperators.append((Settings.shared.operatorNAME, Settings.shared.operatorID))
        
        operatorPopup.removeAllItems()
        operatorPopup.addItems(withTitles: availableOperators.map { $0.name })
        
        //operatorPopup.selectItem(at: availableOperators.count - 1 )
        operatorPopup.selectItem(withTitle: Settings.shared.operatorNAME)
        
        ipVerPopup.selectItem(withTitle: Settings.shared.IPver)
        customDNS.state = Settings.shared.CustomDNS ? .on : .off
        primaryDNSField.stringValue = Settings.shared.PrimaryDNS
        secondaryDNSField.stringValue = Settings.shared.SecondaryDNS
    }
    
    @IBAction func ipChanged(_ sender: NSPopUpButton) {
        if let selected = sender.selectedItem?.title {
            Settings.shared.IPver = selected
        }
    }
    
    @IBAction func atPortChanged(_ sender: NSPopUpButton) {
        if let selected = sender.selectedItem?.title {
            Settings.shared.atPort = "/dev/\(selected)"
        }
    }

    @IBAction func pppPortChanged(_ sender: NSPopUpButton) {
        if let selected = sender.selectedItem?.title {
            Settings.shared.pppPort = "/dev/\(selected)"
        }
    }

    @IBAction func saveClicked(_ sender: Any) {
        //Settings.shared.atPort = atPortPopup.stringValue
        //Settings.shared.pppPort = pppPortPopup.stringValue
        Settings.shared.apn = apnField.stringValue
        Settings.shared.pin = pinField.stringValue
        Settings.shared.baudrate = baudField.stringValue
        Settings.shared.passwd = passwdField.stringValue
        Settings.shared.IPver = ipVerPopup.selectedItem?.title ?? "IP"
        Settings.shared.CustomDNS = customDNS.state == .on
        Settings.shared.PrimaryDNS = primaryDNSField.stringValue
        Settings.shared.SecondaryDNS = secondaryDNSField.stringValue
        self.window?.close()
    }
    
    @IBAction func setOperatorName(_ sender: NSButton) {
        Settings.shared.showOperator = sender.state == .on
    }
    
    func parseCOPSResponse(_ response: String) -> [(name: String, id: String)] {
        var results: [(String, String)] = []
        results.append((NSLocalizedString("Automatically", comment: "auto"), "0"))
        
        let pattern = #"\"([^\"]+)\",\"([^\"]+)\",\"([^\"]+)\",(\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        let matches = regex?.matches(in: response, options: [], range: NSRange(location: 0, length: response.utf16.count)) ?? []

        for match in matches {
            if match.numberOfRanges >= 4,
               let nameRange = Range(match.range(at: 1), in: response),
               let idRange = Range(match.range(at: 3), in: response) {

                let name = String(response[nameRange])
                let id = String(response[idRange])
                results.append((name, id))
            }
        }

        return results
    }
    
    @IBAction func loadOperators(_ sender: Any) {
        if LoadingOperators {
            return
        }
        ModemManager.shared.disUpdates = true
        
        operatorPopup.removeAllItems()
        operatorPopup.addItem(withTitle: NSLocalizedString("Searching...", comment: "searching"))
        LoadingOperators = true
        
        if ModemManager.shared.sendAndRead("AT+CFUN?") != "1" {
            if ModemManager.shared.sendAndRead("AT+CFUN=1") != "OK" {
                print("modem wake error")
                return
            }
            sleep(2)
        }
        
        // Čekat asynchronně
        DispatchQueue.main.async {
            let response = ModemManager.shared.sendAndRead("AT+COPS=?", timeout: 60)
            self.availableOperators = self.parseCOPSResponse(response)
            print(self.availableOperators)
            ModemManager.shared.disUpdates = false
            self.operatorPopup.removeAllItems()
            self.operatorPopup.addItems(withTitles: self.availableOperators.map { $0.name })
            self.operatorPopup.selectItem(withTitle: Settings.shared.operatorNAME)
            self.LoadingOperators = false
        }

    }
    
    @IBAction func operatorChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        if index >= 0 && index < availableOperators.count {
            let selected = availableOperators[index]
            Settings.shared.operatorID      = selected.id
            Settings.shared.operatorNAME    = selected.name
            print("selected operator: \(selected.name) (\(selected.id))")
        }
    }
    
    @IBAction func changeIconColor(_ sender: NSPopUpButton) {
        if let selected = sender.selectedItem?.title {
            switch selected {
            case NSLocalizedString("White", comment: "white"):
                Settings.shared.iconColor = 1
            case NSLocalizedString("Black", comment: "black"):
                Settings.shared.iconColor = 2
            default:
                Settings.shared.iconColor = 0
            }
        }
    }
    
    @IBAction func testATPort(_ sender: NSButton) {
        guard let selectedPort = atPortPopup.selectedItem?.title else {
            showPortTestAlert(title: "Chyba", message: "Není vybrán žádný AT port")
            return
        }
        
        sender.title = "Testování..."
        sender.isEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Settings.shared.testATPort(selectedPort)
            
            DispatchQueue.main.async {
                sender.title = "Test AT"
                sender.isEnabled = true
                
                let alertType: NSAlert.Style = result.success ? .informational : .warning
                self.showPortTestAlert(title: result.success ? "Test AT portu" : "Chyba AT portu",
                                     message: result.message,
                                     style: alertType)
            }
        }
    }
    
    @IBAction func testPPPPort(_ sender: NSButton) {
        guard let selectedPort = pppPortPopup.selectedItem?.title else {
            showPortTestAlert(title: "Chyba", message: "Není vybrán žádný PPP port")
            return
        }
        
        sender.title = "Testování..."
        sender.isEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Settings.shared.testPPPPort(selectedPort)
            
            DispatchQueue.main.async {
                sender.title = "Test PPP"
                sender.isEnabled = true
                
                let alertType: NSAlert.Style = result.success ? .informational : .warning
                self.showPortTestAlert(title: result.success ? "Test PPP portu" : "Chyba PPP portu",
                                     message: result.message,
                                     style: alertType)
            }
        }
    }
    
    private func showPortTestAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        
        if let window = self.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
    /*
     let id = Settings.shared.operatorID
     at.send("AT+COPS=1,2,\"\(id)\"")
     */
    
}
