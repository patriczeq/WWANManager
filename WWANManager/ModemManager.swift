import Foundation
import Darwin

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
