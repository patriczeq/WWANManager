import Foundation
import SystemConfiguration
import Darwin
import Cocoa
import Security

enum PPPConnectionState {
    case disconnected
    case connecting
    case connected
}

class PPPManager {
    static let shared = PPPManager()

    private var task: Process?
    private var chatScriptPath: String?
   
    func isPPPConnected() -> Bool {
            var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?

            guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
                return false
            }

            defer {
                freeifaddrs(ifaddrPtr)
            }

            var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let interface = ptr?.pointee {
                let name = String(cString: interface.ifa_name)

                if name == "ppp0", interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                    getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)

                    let ip = String(cString: hostname)
                    return ip != "0.0.0.0"
                }

                ptr = interface.ifa_next
            }


            return false
        }
    
    func connectionState() -> PPPConnectionState {
        if isPPPConnected() {
            return .connected
        } else if let task = task, task.isRunning {
            return .connecting
        } else {
            return .disconnected
        }
    }
    
    
    func connect() -> Bool {
        guard connectionState() == .disconnected else { return false }

        let pppPort  = Settings.shared.pppPort
        let apn      = Settings.shared.apn
        let baudrate = Settings.shared.baudrate
        let pin      = Settings.shared.pin
        let ipver    = Settings.shared.IPver
        
        // Ověření portů
        if !ModemManager.shared.checkConnection() {
            // alert na ověření portů
            if !ModemManager.shared.atPortStatus {
                let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Port does not exist!", comment: "your account password")
                    alert.informativeText = Settings.shared.atPort
                    alert.alertStyle = NSAlert.Style.critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
            }
            if !ModemManager.shared.pppPortStatus {
                let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Port does not exist!", comment: "your account password")
                    alert.informativeText = Settings.shared.pppPort
                    alert.alertStyle = NSAlert.Style.critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
            }
            return false;
        }
        // Ověření hesla
        if !Settings.shared.checkPasswordValid(for: Settings.shared.passwd) {
            let alert = NSAlert()
                alert.messageText = NSLocalizedString("Bad password!", comment: "your account password")
                alert.alertStyle = NSAlert.Style.critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            return false
        }
        
        // nastavit LTE
        if !ModemManager.shared.isOpen {
            ModemManager.shared.open()
            
            /*// Ověření zda je nutný pin
            
            let pinState = ModemManager.shared.sendAndRead("AT+CPIN?")
            print(pinState)
            
            return false*/
        }
        var COPS_STR = ""
        if Settings.shared.operatorID == "0" {
            COPS_STR = "0"
        } else {
            COPS_STR = "1,2,\"\(Settings.shared.operatorID)\""
        }
        
        // 1. Vytvoříme chat skript
        let script = """
                    ABORT "BUSY"
                    ABORT "NO CARRIER"
                    ABORT "ERROR"
                    '' ATZ
                    \(pin != "" ? "OK AT+CPIN=\"\(pin)\"" : "#NO PIN")
                    OK AT+COPS=\(COPS_STR)
                    OK AT+CGDCONT=1,"IP","\(apn)"
                    OK ATD*99#
                    CONNECT ''
                    """
        
        print(script)
        
        let scriptPath = "/tmp/chat-connect-wwan"
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        
        
        // 2. Vytvoříme shell skript
        let shellScriptPath = "/tmp/run-pppd.sh"
        let shellScript: String
        var password = Settings.shared.passwd
        
        // Pokud není heslo, zobrazíme dialog pro zadání hesla
        if password.isEmpty {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Enter password for sudo", comment: "sudo password prompt")
            alert.informativeText = NSLocalizedString("Enter password for sudo to use this feature.", comment: "sudo password info")
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            
            let inputField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            alert.accessoryView = inputField
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                password = inputField.stringValue
                Settings.shared.passwd = password // volitelně uložit pro další použití
            } else {
                return false
            }
        }
        
        if !password.isEmpty {
            shellScript = """
            #!/bin/bash
            echo \"\(password)\" | sudo -S /usr/sbin/pppd \(pppPort) \(baudrate) debug nodetach usepeerdns connect \"/usr/sbin/chat -v -f \(scriptPath)\"
            """
        } else {
            shellScript = """
            #!/bin/bash
            sudo /usr/sbin/pppd \(pppPort) \(baudrate) debug nodetach usepeerdns connect \"/usr/sbin/chat -v -f \(scriptPath)\"
            """
        }
        try? shellScript.write(toFile: shellScriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellScriptPath)

        // 3. Spuštění shell skriptu přímo přes Process (bez osascript)
        task = Process()
        task?.executableURL = URL(fileURLWithPath: "/bin/bash")
        task?.arguments = [shellScriptPath]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task?.standardOutput = outputPipe
        task?.standardError = errorPipe
        do {
            try task?.run()
            print("Running pppd script directly via bash")
        } catch {
            print("error running pppd: \(error)")
        }
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                print("pppd stdout: \(str)")
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                print("pppd stderr: \(str)")
            }
        }
        
        ModemManager.shared.updateOperatorName()
        return true
    }


    func disconnect() { // resetnem modem?
        ModemManager.shared.open()
        ModemManager.shared.send(command: "AT+CFUN=1,1")
        ModemManager.shared.close()
        //ModemManager.shared.send(command: "+++")
        sleep(1)
        //ModemManager.shared.send(command: "ATH")
        task?.terminate()
        task = nil

        if let scriptPath = chatScriptPath {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }
    }
}
