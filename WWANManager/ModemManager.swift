import Foundation
import Darwin
import IOKit

enum SignalStrengthLevel: String {
    case none = "Žádný"
    case poor = "Slabý"
    case fair = "Střední"
    case good = "Silný"
    case excellent = "Výborný"
}


class ModemManager {
    static let shared = ModemManager()

    private var fd: Int32 = -1
    
    var isOpen: Bool {
        return fd >= 0
    }
    
    var _rssi: Int = 0
    
    var disUpdates: Bool = false
    
    var atPortStatus: Bool = false
    var pppPortStatus: Bool = false
    var pinRequired: Bool = true
    
    // MARK: - ACPI / Kext operations

    private func kextResultString(_ result: WWANACPIResult) -> String {
        if result == kWWANACPISuccess          { return "OK" }
        if result == kWWANACPIErrorNotFound    { return "ERROR: kext not found — load WWANACPIKext.kext first" }
        if result == kWWANACPIErrorConnection  { return "ERROR: failed to connect to kext" }
        if result == kWWANACPIErrorExecution   { return "ERROR: ACPI execution failed" }
        return "ERROR: unknown (\(result.rawValue))"
    }

    func wakeWWAN() {
        print("WWAN: ModemOn (PINI sequence)...")
        let result = WWANACPIHelper_ModemOn()
        print("WWAN: ModemOn -> \(kextResultString(result))")
    }

    func modemOff() {
        print("WWAN: ModemOff (DL23 sequence)...")
        let result = WWANACPIHelper_ModemOff()
        print("WWAN: ModemOff -> \(kextResultString(result))")
    }

    func modemReset() {
        print("WWAN: Reset (off + 500ms + on)...")
        let result = WWANACPIHelper_Reset()
        print("WWAN: Reset -> \(kextResultString(result))")
    }

    func switchUSBMode() {
        print("WWAN: SwitchUSBMode...")
        let result = WWANACPIHelper_SwitchUSBMode()
        print("WWAN: SwitchUSBMode -> \(kextResultString(result))")
    }

    func detectMode() -> String {
        var mode = kWWANModeUnknown
        let result = WWANACPIHelper_DetectMode(&mode)
        if result != kWWANACPISuccess {
            return "Unknown (\(kextResultString(result)))"
        }
        switch mode {
        case kWWANModePCIe:    return "PCIe"
        case kWWANModeUSB:     return "USB"
        case kWWANModeOff:     return "Off"
        default:               return "Unknown"
        }
    }

    // MARK: - Hardware modem state for UI

    enum HardwareState {
        case on       // USB mode, TTY present — fully operational
        case usb      // USB mode, no TTY yet — enumerating
        case pcie     // PCIe mode — active but not usable by macOS modem stack
        case sleep    // Off / L2L3 — low power
        case unknown  // kext not available or undetectable

        var label: String {
            switch self {
            case .on:      return "On"
            case .usb:     return "USB"
            case .pcie:    return "PCIe"
            case .sleep:   return "Sleep"
            case .unknown: return "Unknown"
            }
        }

        var modeLabel: String {
            switch self {
            case .on:      return "USB"
            case .usb:     return "USB"
            case .pcie:    return "PCIe"
            case .sleep:   return "Off"
            case .unknown: return "—"
            }
        }
    }

    func hardwareState() -> HardwareState {
        var mode = kWWANModeUnknown
        let result = WWANACPIHelper_DetectMode(&mode)
        guard result == kWWANACPISuccess else { return .unknown }

        switch mode {
        case kWWANModeOff:
            return .sleep
        case kWWANModePCIe:
            return .pcie
        case kWWANModeUSB:
            // check if TTY is present
            let devs = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
            let hasTTY = devs.contains { $0.hasPrefix("wwan") || $0.hasPrefix("ttyACM") }
            return hasTTY ? .on : .usb
        default:
            return .unknown
        }
    }

    func modemSleep() {
        print("WWAN: Sleep (DL23 — L2/L3)...")
        let result = WWANACPIHelper_ModemOff()
        print("WWAN: Sleep -> \(kextResultString(result))")
    }

    func modemWake() {
        print("WWAN: Wake (PINI + PXSX._RST)...")
        let result = WWANACPIHelper_ModemOn()
        print("WWAN: Wake -> \(kextResultString(result))")
    }

    // MARK: - Startup initialization

    private func modeString(_ mode: WWANMode) -> String {
        switch mode {
        case kWWANModePCIe:    return "PCIe"
        case kWWANModeUSB:     return "USB"
        case kWWANModeOff:     return "Off"
        default:               return "Unknown"
        }
    }

    /// Sends AT+GTUSBMODE=7 + AT+CFUN=15 via first available /dev/ttyACM*
    /// Returns true if successfully sent
    private func sendGTUSBMode7() -> Bool {
        let devs = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let acmPorts = devs.filter { $0.hasPrefix("ttyACM") }.sorted().map { "/dev/\($0)" }

        for port in acmPorts {
            print("[WWAN Init]   Trying \(port) for AT+GTUSBMODE=7...")
            let tfd = Darwin.open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard tfd >= 0 else { continue }
            defer { Darwin.close(tfd) }

            var options = termios()
            tcgetattr(tfd, &options)
            cfmakeraw(&options)
            cfsetspeed(&options, speed_t(B115200))
            options.c_cflag |= tcflag_t(CLOCAL | CREAD)
            tcsetattr(tfd, TCSANOW, &options)

            func atCmd(_ cmd: String) -> String {
                let full = cmd + "\r"
                _ = full.withCString { write(tfd, $0, strlen($0)) }
                Thread.sleep(forTimeInterval: 0.4)
                var buf = [UInt8](repeating: 0, count: 256)
                let n = read(tfd, &buf, 256)
                guard n > 0, let resp = String(bytes: buf[0..<n], encoding: .utf8) else { return "" }
                return resp.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let q = atCmd("AT+GTUSBMODE?")
            print("[WWAN Init]   AT+GTUSBMODE? -> \(q)")
            let r1 = atCmd("AT+GTUSBMODE=7")
            print("[WWAN Init]   AT+GTUSBMODE=7 -> \(r1)")
            let r2 = atCmd("AT+CFUN=15")
            print("[WWAN Init]   AT+CFUN=15 -> \(r2) (modem rebooting into MBIM mode...)")
            return true
        }

        print("[WWAN Init]   No /dev/ttyACM* found")
        return false
    }

    func initializeModem() {
        print("[WWAN Init] ──────────────────────────────")
        print("[WWAN Init] Starting modem initialization...")

        // Step 1: Detect current mode
        print("[WWAN Init] Step 1: Detecting modem mode...")
        var mode = kWWANModeUnknown
        let detectResult = WWANACPIHelper_DetectMode(&mode)

        if detectResult != kWWANACPISuccess {
            print("[WWAN Init] ⚠️  Kext not available (\(kextResultString(detectResult))) — skipping ACPI init")
            print("[WWAN Init] ──────────────────────────────")
            return
        }
        print("[WWAN Init] Current mode: \(modeString(mode))")

        // ── Exact xmm2usb sequence: ───────────────────────────────────────
        //   setpci -s RP07 CAP_EXP+10.w=0052   →  kext modemOn() step 1
        //   acpi_call _SB.PCI0.RP07.PXSX._RST  →  kext modemOn() step 2
        //   wait 5–10s for USB re-enumeration
        //   if ttyACM appears but no MBIM: AT+GTUSBMODE=7 + AT+CFUN=15
        // ─────────────────────────────────────────────────────────────────

        switch mode {

        case kWWANModeUSB:
            print("[WWAN Init] Step 2: USB mode — checking TTY...")
            if checkConnection() {
                print("[WWAN Init] ✅ TTY present — nothing to do")
                print("[WWAN Init] Initialization complete")
                print("[WWAN Init] ──────────────────────────────")
                return
            }
            // USB but no configured TTY — check for ttyACM (modem in ACM but wrong GTUSBMODE)
            let devs = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
            if devs.contains(where: { $0.hasPrefix("ttyACM") }) {
                print("[WWAN Init]   ttyACM present — sending AT+GTUSBMODE=7...")
                if sendGTUSBMode7() {
                    print("[WWAN Init]   Waiting 10s for modem reboot into MBIM mode...")
                    Thread.sleep(forTimeInterval: 10.0)
                }
            } else {
                // No ttyACM at all = bDeviceClass=224, needs PINI/SBR cycle
                print("[WWAN Init]   No ttyACM (modem in wrong class) — PINI/SBR cycle...")
                let r = WWANACPIHelper_ModemOn()
                print("[WWAN Init]   PINI/SBR -> \(kextResultString(r))")
                print("[WWAN Init]   Waiting 10s...")
                Thread.sleep(forTimeInterval: 10.0)
            }

        case kWWANModePCIe:
            // xmm2usb sequence: CAP_EXP+10=0x52 then PXSX._RST
            print("[WWAN Init] Step 2: PCIe mode — xmm2usb (CAP_EXP+10=0x52 + PXSX._RST)...")
            let r = WWANACPIHelper_ModemOn()
            print("[WWAN Init]   ModemOn -> \(kextResultString(r))")
            if r == kWWANACPISuccess {
                print("[WWAN Init]   Waiting 10s for USB enumeration (xmm7360 needs 5–10s)...")
                Thread.sleep(forTimeInterval: 10.0)
            }

        default:
            print("[WWAN Init] Step 2: Modem Off/Unknown — xmm2usb sequence...")
            let r = WWANACPIHelper_ModemOn()
            print("[WWAN Init]   ModemOn -> \(kextResultString(r))")
            if r == kWWANACPISuccess {
                print("[WWAN Init]   Waiting 10s...")
                Thread.sleep(forTimeInterval: 10.0)
            }
        }

        // Step 3: Check for ttyACM — if present, send GTUSBMODE=7 if not yet done
        print("[WWAN Init] Step 3: Checking TTY...")
        if checkConnection() {
            print("[WWAN Init] ✅ TTY present!")
        } else {
            let devs2 = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
            let hasACM = devs2.contains { $0.hasPrefix("ttyACM") }
            if hasACM {
                print("[WWAN Init]   /dev/ttyACM* found — sending AT+GTUSBMODE=7 + AT+CFUN=15...")
                if sendGTUSBMode7() {
                    print("[WWAN Init]   Waiting 10s for modem reboot into MBIM mode...")
                    Thread.sleep(forTimeInterval: 10.0)
                }
            } else {
                print("[WWAN Init] ⚠️  No TTY — modem still in bDeviceClass=224 (wrong USB mode)")
                print("[WWAN Init] ℹ️  FIRST TIME: Boot Linux → sudo ./xmm2usb → screen /dev/ttyACM0")
                print("[WWAN Init]    → AT+GTUSBMODE=7 → AT+CFUN=15  (one-time permanent change)")
            }
        }

        // Final check
        print("[WWAN Init] Final mode check...")
        var finalMode = kWWANModeUnknown
        _ = WWANACPIHelper_DetectMode(&finalMode)
        let ttyOK = checkConnection()
        print("[WWAN Init] Final mode: \(modeString(finalMode)) | TTY: \(ttyOK ? "✅" : "❌")")
        print("[WWAN Init] Initialization complete")
        print("[WWAN Init] ──────────────────────────────")
    }


    
    func checkConnection() -> Bool {
        let fileManager = FileManager.default
        
        atPortStatus = fileManager.fileExists(atPath: Settings.shared.atPort)
        pppPortStatus = fileManager.fileExists(atPath: Settings.shared.pppPort)
        
        return atPortStatus && pppPortStatus
    }
    
    func listAvailablePorts() -> [String] {
        let contents = try? FileManager.default.contentsOfDirectory(atPath: "/dev")
        return contents?.filter { $0.contains("usbmodem") || $0.contains("tty") || $0.contains("cu") } ?? []
    }

    func open() {
        close()

        let atPort = Settings.shared.atPort
        fd = Darwin.open(atPort, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            print("AT port open error")
            return
        }

        var options = termios()
        tcgetattr(fd, &options)

        cfmakeraw(&options)
        cfsetspeed(&options, speed_t(B115200))
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cc.16 /* VMIN */ = 0
        options.c_cc.17 /* VTIME */ = 1

        tcsetattr(fd, TCSANOW, &options)

        print("AT port opened: \(atPort)")
    }

    func send(command: String) {
        guard fd >= 0 else { return }
        let fullCommand = command + "\r"
        _ = fullCommand.withCString {
            write(fd, $0, strlen($0))
        }
    }

    func readResponse(timeout: TimeInterval = 0.5) -> String? {
        guard fd >= 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 1024)
        let start = Date()
        var result = ""

        repeat {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                if let part = String(bytes: buffer[0..<count], encoding: .utf8) {
                    result += part
                }
            } else {
                usleep(100_000)
            }
        } while Date().timeIntervalSince(start) < timeout

        // Odfiltruj echo příkazů typu "AT+..." a nech jen odpovědi
        let lines = result.components(separatedBy: .newlines)
        let cleanLines = lines.filter {
            !$0.hasPrefix("AT") && !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }

        return cleanLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }


    func sendAndRead(_ command: String, timeout: TimeInterval = 0.5) -> String {
        if !isOpen{
            open()
        }
        send(command: command)
        return readResponse(timeout: timeout) ?? "<no response>"
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
    
    var operatorName: String? = nil
    var networkTechnology: String = "Unknown"
    var cellId: String = ""
    var lac: String = ""
    var band: String = ""

    func updateOperatorName() {
        //open()
        let response = sendAndRead("AT+COPS?")
        if let match = response.range(of: "\"([^\"]+)\"", options: .regularExpression) {
            operatorName = String(response[match]).replacingOccurrences(of: "\"", with: "")
        } else {
            operatorName = ""
        }
        //close()
    }
    
    func getNetworkTechnology() -> String {
        // Zkus různé AT příkazy pro detekci technologie
        var response = sendAndRead("AT+COPS?")
        
        // Zkus AT+CREG? pro registraci a technologii
        response = sendAndRead("AT+CREG?")
        if response.contains("2,1") || response.contains("2,5") {
            // Registrován na síti
            let techResponse = sendAndRead("AT+XRAT?")
            if techResponse.contains("7") {
                return "LTE"
            } else if techResponse.contains("2") {
                return "UMTS/3G"
            } else if techResponse.contains("0") {
                return "GSM/2G"
            }
        }
        
        // Alternativní metoda přes AT+CEREG pro LTE
        response = sendAndRead("AT+CEREG?")
        if response.contains("1") || response.contains("5") {
            return "LTE"
        }
        
        // Zkus AT+CGACT? pro aktivní PDP kontext
        response = sendAndRead("AT+CGACT?")
        if response.contains("1,1") {
            // Aktivní kontext, zkus zjistit technologii
            let serviceResponse = sendAndRead("AT+CPSI?")
            if serviceResponse.contains("LTE") {
                return "LTE"
            } else if serviceResponse.contains("WCDMA") {
                return "3G/WCDMA"
            } else if serviceResponse.contains("GSM") {
                return "2G/GSM"
            }
        }
        
        return "Unknown"
    }
    
    func getCellInfo() -> (cellId: String, lac: String, band: String) {
        var cellId = ""
        var lac = ""
        var band = ""
        
        // Zkus získat Cell ID a LAC
        let cregResponse = sendAndRead("AT+CREG?")
        // Parsing pro +CREG: 2,1,"LAC","CellID"
        if let match = cregResponse.range(of: #"\+CREG:\s*\d+,\d+,"([^"]+)","([^"]+)""#, options: .regularExpression) {
            let components = cregResponse[match].components(separatedBy: "\"")
            if components.count >= 4 {
                lac = components[1]
                cellId = components[3]
            }
        }
        
        // Zkus získat informace o pásmu
        let bandResponse = sendAndRead("AT+CPSI?")
        if bandResponse.contains("LTE") {
            // Parsing pro LTE band info
            if let bandMatch = bandResponse.range(of: #"LTE.*?(\d+)"#, options: .regularExpression) {
                band = "LTE B" + String(bandResponse[bandMatch].components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
            }
        } else if bandResponse.contains("WCDMA") {
            band = "WCDMA"
        } else if bandResponse.contains("GSM") {
            band = "GSM"
        }
        
        return (cellId, lac, band)
    }
    
    func getCarrierAggregationInfo() -> String {
        let response = sendAndRead("AT+CPSI?")
        if response.contains("CA") {
            return "Enabled"
        }
        return "Disabled"
    }
    
    func setLTEPlusAllBands() -> String {
        var results: [String] = []
        
        results.append("1. Setting LTE as primary...")
        let xactResult = sendAndRead("AT+XACT=4,2")
        results.append("AT+XACT=4,2: \(xactResult)")
        
        if xactResult.contains("OK") {
            // Try different approaches for enabling all bands
            results.append("\n2. Trying to enable automatic band selection...")
            
            // Option A: Try AT+XACT=6 (Auto mode with all bands)
            let autoResult = sendAndRead("AT+XACT=6", timeout: 2.0)
            results.append("AT+XACT=6 (Auto GSM+WCDMA+LTE): \(autoResult)")
            
            if autoResult.contains("ERROR") {
                // Option B: Try AT+XACT=4 without the second parameter
                results.append("\n3. Trying LTE+WCDMA mode...")
                let lteWcdmaResult = sendAndRead("AT+XACT=4", timeout: 2.0)
                results.append("AT+XACT=4 (LTE+WCDMA): \(lteWcdmaResult)")
                
                if lteWcdmaResult.contains("ERROR") {
                    // Keep original LTE primary setting
                    results.append("\n4. Keeping original LTE primary setting...")
                    results.append("Your modem may not support automatic band selection.")
                    results.append("AT+XACT=4,2 should provide good LTE coverage.")
                } else {
                    results.append("\nSuccess! LTE+WCDMA mode enabled for better compatibility.")
                }
            } else {
                results.append("\nSuccess! Automatic mode (GSM+WCDMA+LTE) enabled.")
            }
            
        } else {
            results.append("\nERROR: LTE configuration failed!")
        }
        
        return results.joined(separator: "\n")
    }
    

    
    func getDataUsage() -> (rx: String, tx: String) {
        // Někdy modemy podporují AT+CGDCONT? pro data usage
        let response = sendAndRead("AT+CGDCONT?")
        // Toto je zjednodušené - skutečné parsování závisí na modemu
        return ("N/A", "N/A")
    }
    
    func getSignalStrength() -> (level: SignalStrengthLevel, rssi: Int)? {
        let response = sendAndRead("AT+CSQ")
        
        guard let match = response.range(of: #"(\+CSQ:\s*)(\d+),"#, options: .regularExpression) else {
            return nil
        }

        let components = response[match].components(separatedBy: CharacterSet.decimalDigits.inverted)
        guard let rssiStr = components.first(where: { !$0.isEmpty }),
              let rssi = Int(rssiStr) else {
            return nil
        }
        
        self._rssi = rssi

        let level: SignalStrengthLevel
        switch rssi {
            case 1...9:     level = .poor      // -111 až -93 dBm
            case 10...14:   level = .fair      // -91 až -83 dBm
            case 15...19:   level = .good      // -81 až -73 dBm
            case 20...31:   level = .excellent // -71 až -51 dBm
            default:        level = .none
        }

        return (level, rssi)
    }
    
}
