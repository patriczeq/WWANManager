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
    private var connectionStartTime: Date?
    private var connectionTimer: Timer?

    // Statistiky připojení
    private var totalBytesReceived: UInt64 = 0
    private var totalBytesSent: UInt64 = 0
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastUpdateTime: Date?
    private var currentSpeedIn: Double = 0.0
    private var currentSpeedOut: Double = 0.0
    private var connectionDuration: TimeInterval = 0

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
        let peerDNS  = !Settings.shared.CustomDNS
        
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
        
        // Kontrola dostupných PDP kontextů
        print("Checking available PDP contexts...")
        let cgdcontTest = ModemManager.shared.sendAndRead("AT+CGDCONT=?")
        print("AT+CGDCONT=? response: \(cgdcontTest)")
        
        let cgdcontCurrent = ModemManager.shared.sendAndRead("AT+CGDCONT?")
        print("AT+CGDCONT? current contexts: \(cgdcontCurrent)")
        
        // Kontrola IPv6 podpory
        let cgcontrdpTest = ModemManager.shared.sendAndRead("AT+CGCONTRDP=?")
        print("AT+CGCONTRDP=? response: \(cgcontrdpTest)")
        
        var COPS_STR = ""
        if Settings.shared.operatorID == "0" {
            COPS_STR = "0"
        } else {
            COPS_STR = "1,2,\"\(Settings.shared.operatorID)\""
        }
        
        // Určení správného PDP typu podle nastavení
        var pdpType: String
        switch ipver {
        case "IP":
            pdpType = "IP"
        case "IPV6":
            pdpType = "IPV6"
        case "IPV4V6":
            pdpType = "IPV4V6"
        default:
            pdpType = "IP" // výchozí fallback
        }
        
        // Experimentální: nastavení více kontextů pro lepší IPv6 podporu
        if ipver == "IPV4V6" {
            // Zkusíme nastavit separátní kontexty pro IPv4 a IPv6
            let clearContexts = ModemManager.shared.sendAndRead("AT+CGDCONT=0")
            print("Clearing contexts: \(clearContexts)")
            
            let setIPv4Context = ModemManager.shared.sendAndRead("AT+CGDCONT=1,\"IP\",\"\(apn)\"")
            print("Setting IPv4 context: \(setIPv4Context)")
            
            let setIPv6Context = ModemManager.shared.sendAndRead("AT+CGDCONT=2,\"IPV6\",\"\(apn)\"")
            print("Setting IPv6 context: \(setIPv6Context)")
            
            // Zkontrolujeme nastavené kontexty
            let verifyContexts = ModemManager.shared.sendAndRead("AT+CGDCONT?")
            print("Verified contexts: \(verifyContexts)")
        }
        
        // 1. Vytvoříme chat skript
        var script = """
                    ABORT "BUSY"
                    ABORT "NO CARRIER"
                    ABORT "ERROR"
                    '' ATZ
                    """
        if pin != "" {
            script += """
                    \nOK AT+CPIN=\"\(pin)\"
                    """
        }
        script += """
                \nOK AT+COPS=\(COPS_STR)
                OK AT+CGDCONT=1,"\(pdpType)","\(apn)"
                OK ATD*99#
                CONNECT ''
                """
        print("\nChat script:")
        print("------------------------------")
        print(script)
        print("------------------------------")
        print("EOF chat script\n")
        
        let scriptPath = "/tmp/chat-connect-wwan"
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        
        
        // 2. Vytvoříme shell skript
        let shellScriptPath = "/tmp/run-pppd.sh"
        var shellScript: String
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
        shellScript = "#!/bin/bash\n"
        if !password.isEmpty {
            shellScript += "echo \"\(password)\" | sudo -S "
        } else {
            shellScript += "sudo "
        }
        shellScript += "/usr/sbin/pppd \(pppPort) \(baudrate) debug nodetach"
        if peerDNS {
            shellScript += " usepeerdns"
        } else {
            // Přidání custom DNS serverů - podle man pppd
            let primaryDNS = Settings.shared.PrimaryDNS.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondaryDNS = Settings.shared.SecondaryDNS.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !primaryDNS.isEmpty {
                shellScript += " ms-dns \(primaryDNS)"
                print("Using custom primary DNS: \(primaryDNS)")
            }
            
            if !secondaryDNS.isEmpty {
                shellScript += " ms-dns \(secondaryDNS)"
                print("Using custom secondary DNS: \(secondaryDNS)")
            }
            
            // Pokud nejsou nastavené žádné DNS servery, použijeme výchozí
            if primaryDNS.isEmpty && secondaryDNS.isEmpty {
                shellScript += " ms-dns 8.8.8.8 ms-dns 8.8.4.4"
                print("No custom DNS set, using Google DNS as fallback")
            }
        }
        // Přidání IP verze
        if ipver == "IP" {
            // IPv4 pouze - žádné další parametry nejsou potřeba (výchozí)
        } else if ipver == "IPV6" {
            shellScript += " ipv6 ::1,::2"
        } else if ipver == "IPV4V6" {
            shellScript += " ipv6 ::1,::2"
        }
        shellScript += " connect \"/usr/sbin/chat -v -f \(scriptPath)\""
        
        print("Shell script:")
        print("------------------------------")
        print(shellScript)
        print("------------------------------")
        
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
            
            // Spustit timeout monitoring
            connectionStartTime = Date()
            startConnectionMonitoring()
            
        } catch {
            print("error running pppd: \(error)")
        }
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                print("pppd stdout: \(str)")
                
                // Pokud se úspěšně připojíme a máme IPv6, zkusíme získat globální IPv6 adresu
                if str.contains("local  LL address") && ipver != "IP" {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        self.configureIPv6Interface()
                    }
                }
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
    
    private func checkIPv6Connectivity() -> (hasIPv4: Bool, hasPublicIPv6: Bool) {
        var hasIPv4 = false
        var hasPublicIPv6 = false
        
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return (false, false)
        }
        defer { freeifaddrs(ifaddrPtr) }
        
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let interface = ptr?.pointee {
            let name = String(cString: interface.ifa_name)
            
            if name == "ppp0" {
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    hasIPv4 = true
                } else if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET6) {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    
                    getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    
                    let ipv6 = String(cString: hostname)
                    // Kontrola zda není link-local (fe80::)
                    if !ipv6.hasPrefix("fe80:") && ipv6 != "::1" {
                        hasPublicIPv6 = true
                    }
                }
            }
            ptr = interface.ifa_next
        }
        
        return (hasIPv4, hasPublicIPv6)
    }
    
    private func configureIPv6Interface() {
        print("🔧 Attempting to configure IPv6 for ppp0...")
        
        // Nejdříve zkusíme aktivovat IPv6 na interface
        let enableIPv6Script = """
        #!/bin/bash
        echo "\(Settings.shared.passwd)" | sudo -S sysctl -w net.inet6.ip6.forwarding=1
        echo "\(Settings.shared.passwd)" | sudo -S sysctl -w net.inet6.ip6.accept_rtadv=1
        echo "\(Settings.shared.passwd)" | sudo -S ifconfig ppp0 inet6 -ifdisabled
        echo "\(Settings.shared.passwd)" | sudo -S ifconfig ppp0 inet6 auto_linklocal
        
        # Zkusíme získat Router Advertisement
        echo "\(Settings.shared.passwd)" | sudo -S rtsol ppp0 2>/dev/null || true
        
        # Počkáme na konfigurace
        sleep 3
        
        # Zobrazíme výsledek
        ifconfig ppp0 | grep inet6
        """
        
        let scriptPath = "/tmp/configure-ipv6.sh"
        try? enableIPv6Script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("IPv6 configuration result:")
                print(output)
            }
            
            // Kontrola zda máme nyní globální IPv6
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                let result = self.checkIPv6Connectivity()
                if result.hasPublicIPv6 {
                    print("✅ IPv6 successfully configured!")
                } else {
                    print("⚠️  IPv6 configuration failed - provider may not support IPv6")
                    print("💡 Try switching to Windows mode or contact Vodafone support")
                }
            }
            
        } catch {
            print("Error configuring IPv6: \(error)")
        }
        
        // Vyčistíme dočasný skript
        try? FileManager.default.removeItem(atPath: scriptPath)
    }
    
    private func startConnectionMonitoring() {
        connectionTimer?.invalidate() // Zrušit předchozí timer, pokud existuje
        
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
            guard let startTime = self.connectionStartTime else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            
            // KLÍČOVÁ OPRAVA: Pokud jsme se úspěšně připojili, zrušíme monitoring
            if self.isPPPConnected() {
                print("✅ Successfully connected! Stopping timeout monitoring.")
                self.connectionStartTime = nil
                self.resetStatistics()
                self.startStatisticsMonitoring()
                timer.invalidate()
                return
            }
            
            print("Connection attempt in progress... Elapsed time: \(elapsed) seconds")
            
            // Pokud připojení trvá déle než 60 sekund A STÁLE NEJSME PŘIPOJENI, ukončíme proces
            if elapsed > 60 {
                print("🔴 Connection attempt timed out after 60 seconds. Terminating application...")
                
                // Force terminate pppd proces
                self.task?.terminate()
                self.task?.interrupt()
                
                // Reset modemu
                ModemManager.shared.open()
                ModemManager.shared.send(command: "AT+CFUN=1,1")
                ModemManager.shared.close()
                
                // Zobrazit alert uživateli
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Connection Timeout - Application will exit", comment: "connection timeout fatal error")
                    alert.informativeText = NSLocalizedString("Failed to establish connection after 60 seconds. The application will be terminated to prevent hanging processes.", comment: "connection timeout fatal info")
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "Exit Application")
                    alert.runModal()
                    
                    // UKONČIT CELOU APLIKACI
                    print("🔴 TERMINATING APPLICATION DUE TO CONNECTION TIMEOUT")
                    NSApplication.shared.terminate(nil)
                }
                
                // Resetovat stav
                self.connectionStartTime = nil
                timer.invalidate()
            }
        }
    }
    
    // MARK: - Statistiky připojení
    
    private func resetStatistics() {
        totalBytesReceived = 0
        totalBytesSent = 0
        lastBytesIn = 0
        lastBytesOut = 0
        lastUpdateTime = Date()
        currentSpeedIn = 0.0
        currentSpeedOut = 0.0
        connectionStartTime = Date()
    }
    
    private func startStatisticsMonitoring() {
        connectionTimer?.invalidate()
        
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.isPPPConnected() {
                self.updateStatistics()
            } else {
                // Připojení bylo ztraceno
                timer.invalidate()
                self.connectionTimer = nil
                self.connectionStartTime = nil
            }
        }
    }
    
    private func updateStatistics() {
        guard let (bytesIn, bytesOut) = getNetworkInterfaceStatistics(interface: "ppp0") else {
            return
        }
        
        let currentTime = Date()
        
        if lastUpdateTime != nil {
            let timeDiff = currentTime.timeIntervalSince(lastUpdateTime!)
            
            if timeDiff > 0 {
                // Vypočítat rychlost
                let bytesDiffIn = bytesIn > lastBytesIn ? bytesIn - lastBytesIn : 0
                let bytesDiffOut = bytesOut > lastBytesOut ? bytesOut - lastBytesOut : 0
                
                currentSpeedIn = Double(bytesDiffIn) / timeDiff
                currentSpeedOut = Double(bytesDiffOut) / timeDiff
                
                // Aktualizovat celkové statistiky
                totalBytesReceived = bytesIn
                totalBytesSent = bytesOut
            }
        }
        
        lastBytesIn = bytesIn
        lastBytesOut = bytesOut
        lastUpdateTime = currentTime
        
        // Aktualizovat dobu připojení
        if let startTime = connectionStartTime {
            connectionDuration = currentTime.timeIntervalSince(startTime)
        }
    }
    
    private func getNetworkInterfaceStatistics(interface: String) -> (bytesIn: UInt64, bytesOut: UInt64)? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return nil
        }
        
        defer {
            freeifaddrs(ifaddrPtr)
        }
        
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ifaddr = ptr?.pointee {
            let name = String(cString: ifaddr.ifa_name)
            
            if name == interface && ifaddr.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                let data = ifaddr.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
                if let data = data {
                    return (bytesIn: UInt64(data.ifi_ibytes), bytesOut: UInt64(data.ifi_obytes))
                }
            }
            
            ptr = ifaddr.ifa_next
        }
        
        return nil
    }
    
    // MARK: - Veřejné metody pro získání statistik
    
    func getCurrentSpeed() -> (downloadKbps: Double, uploadKbps: Double) {
        return (currentSpeedIn * 8 / 1024, currentSpeedOut * 8 / 1024) // převod na Kbps
    }
    
    func getFormattedDataUsage() -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        
        let received = formatter.string(fromByteCount: Int64(totalBytesReceived))
        let sent = formatter.string(fromByteCount: Int64(totalBytesSent))
        
        return "↓ \(received) ↑ \(sent)"
    }
    
    func getFormattedSpeed() -> String {
        let (download, upload) = getCurrentSpeed()
        
        func formatSpeed(_ speed: Double) -> String {
            if speed > 1024 {
                return String(format: "%.1f Mbps", speed / 1024)
            } else {
                return String(format: "%.0f Kbps", speed)
            }
        }
        
        return "↓ \(formatSpeed(download)) ↑ \(formatSpeed(upload))"
    }
    
    func getFormattedConnectionTime() -> String {
        guard connectionDuration > 0 else { return "00:00:00" }
        
        let hours = Int(connectionDuration) / 3600
        let minutes = (Int(connectionDuration) % 3600) / 60
        let seconds = Int(connectionDuration) % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
