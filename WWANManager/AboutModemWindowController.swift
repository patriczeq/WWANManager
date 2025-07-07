import Cocoa

enum InfoATCommand: String {
    case model      = "CGMM"
    case firmware   = "GMR"
    case imei       = "CGSN"
    case serial     = "GSN"
    case simStatus  = "CPIN?"
    case simNumber  = "CNUM"
    case regStatus  = "CREG?"
    case cops       = "COPS?"
}

class AboutModemWindowController: NSWindowController {
    static let shared = AboutModemWindowController(windowNibName: "AboutModemWindowController")

    @IBOutlet weak var modelField: NSTextField!
    @IBOutlet weak var firmwareField: NSTextField!
    @IBOutlet weak var imeiField: NSTextField!
    @IBOutlet weak var serialField: NSTextField!
    @IBOutlet weak var simStatusField: NSTextField!
    @IBOutlet weak var simNumberField: NSTextField!
    @IBOutlet weak var registrationField: NSTextField!
    @IBOutlet weak var operatorField: NSTextField!
    @IBOutlet weak var refreshButton: NSButton!
    
    @IBOutlet weak var copyrightLabel: NSTextField!
    @IBOutlet weak var versionLabel: NSTextField!
    
    func readModemField(for cmd: InfoATCommand) -> String{
        let _cmd = cmd.rawValue
        return ModemManager.shared.sendAndRead("AT+\(_cmd)")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "+\(_cmd.replacingOccurrences(of: "?", with: "")): ", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @objc func loadModemInfo() {
        // Načtení dat asynchronně
        DispatchQueue.global(qos: .userInitiated).async {
            ModemManager.shared.disUpdates = true
            if !ModemManager.shared.isOpen {
                ModemManager.shared.open()
                let at = ModemManager.shared.sendAndRead("AT")
                print(at)
            }

            let model       = self.readModemField(for: InfoATCommand.model)
            let firmware    = self.readModemField(for: InfoATCommand.firmware)
            let imei        = self.readModemField(for: InfoATCommand.imei)
            let serial      = self.readModemField(for: InfoATCommand.serial)
            let simStatus   = self.readModemField(for: InfoATCommand.simStatus)
            let simNumber   = self.readModemField(for: InfoATCommand.simNumber)
            let reg         = self.readModemField(for: InfoATCommand.regStatus)
            let op          = self.readModemField(for: InfoATCommand.cops)

            DispatchQueue.main.async {
                self.modelField.stringValue = model
                self.firmwareField.stringValue = firmware
                self.imeiField.stringValue = imei
                self.serialField.stringValue = serial
                self.simStatusField.stringValue = simStatus
                self.simNumberField.stringValue = simNumber
                self.registrationField.stringValue = reg
                self.operatorField.stringValue = op
                
                ModemManager.shared.disUpdates = false
            }
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        // Aktivuj aplikaci a přines okno do popředí
        NSApp.activate(ignoringOtherApps: true)

        if let window = self.window {
            window.level = .floating         // Always on top
            window.center()                 // Doprostřed obrazovky
            window.makeKeyAndOrderFront(nil)
        }
        
        // Nastavení copyright a verze
        let infoDict = Bundle.main.infoDictionary
        let version = infoDict?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let copyright = infoDict?["NSHumanReadableCopyright"] as? String ?? ""
        copyrightLabel.stringValue = copyright
        versionLabel.stringValue = "v\(version)"
        
        refreshButton.action = #selector(loadModemInfo)

        loadModemInfo()


    }
}
