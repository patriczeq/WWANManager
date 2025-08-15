import Foundation
import Security
import Darwin

enum ICO_COLOR: Int {
    case color_auto = 0
    case color_white = 1
    case color_black = 2
}

class Settings {
    static let shared = Settings()
    
    var iconColor: Int {
        get { UserDefaults.standard.integer(forKey: "iconColor") }
        set { UserDefaults.standard.setValue(newValue, forKey: "iconColor") }
    }
    var atPort: String {
        get { UserDefaults.standard.string(forKey: "atPort") ?? "/dev/cu.usbmodem14603" }
        set { UserDefaults.standard.setValue(newValue, forKey: "atPort") }
    }

    var pppPort: String {
        get { UserDefaults.standard.string(forKey: "pppPort") ?? "/dev/cu.usbmodem14607" }
        set { UserDefaults.standard.setValue(newValue, forKey: "pppPort") }
    }

    var apn: String {
        get { UserDefaults.standard.string(forKey: "apn") ?? "internet" }
        set { UserDefaults.standard.setValue(newValue, forKey: "apn") }
    }
    
    var baudrate: String {
        get { UserDefaults.standard.string(forKey: "baudrate") ?? "460800" }
        set { UserDefaults.standard.setValue(newValue, forKey: "baudrate") }
    }

    var pin: String {
        get { UserDefaults.standard.string(forKey: "pin") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "pin") }
    }
    
    var passwd: String {
        get { UserDefaults.standard.string(forKey: "passwd") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "passwd") }
    }
    
    var operatorID: String {
        get { UserDefaults.standard.string(forKey: "operatorID") ?? "0" }
        set { UserDefaults.standard.setValue(newValue, forKey: "operatorID") }
    }
    
    var operatorNAME: String {
        get { UserDefaults.standard.string(forKey: "operatorNAME") ?? "Automaticky" }
        set { UserDefaults.standard.setValue(newValue, forKey: "operatorNAME") }
    }
    
    var IPver: String {
        get { UserDefaults.standard.string(forKey: "IPver") ?? "IP" }
        set { UserDefaults.standard.setValue(newValue, forKey: "IPver") }
    }
    
    var CustomDNS: Bool {
        get { UserDefaults.standard.bool(forKey: "CustomDNS") }
        set { UserDefaults.standard.setValue(newValue, forKey: "CustomDNS") }
    }
    
    var PrimaryDNS: String {
        get { UserDefaults.standard.string(forKey: "PrimaryDNS") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "PrimaryDNS") }
    }
    
    var SecondaryDNS: String {
        get { UserDefaults.standard.string(forKey: "SecondaryDNS") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "SecondaryDNS") }
    }
    
    var showOperator: Bool {
        get { UserDefaults.standard.bool(forKey: "showOperator") }
        set { UserDefaults.standard.setValue(newValue, forKey: "showOperator") }
    }
    
    func checkPasswordValid(for password: String) -> Bool {
        let username = NSUserName()

        // Konverze Swift String -> C String (UnsafePointer<Int8>)
        guard let usernameCString = strdup(username),
              let passwordCString = strdup(password) else {
            return false
        }

        // Zajistí uvolnění paměti
        defer {
            free(usernameCString)
            free(passwordCString)
        }

        // Vytvoření AuthorizationItem položek
        var envItems = [
            AuthorizationItem(name: kAuthorizationEnvironmentUsername,
                              valueLength: strlen(usernameCString),
                              value: UnsafeMutableRawPointer(mutating: usernameCString),
                              flags: 0),
            AuthorizationItem(name: kAuthorizationEnvironmentPassword,
                              valueLength: strlen(passwordCString),
                              value: UnsafeMutableRawPointer(mutating: passwordCString),
                              flags: 0)
        ]

        // AuthorizationEnvironment z výše vytvořených položek
        var environment = AuthorizationEnvironment(count: 2, items: &envItems)
        var emptyRights = AuthorizationRights(count: 0, items: nil)
        var authRef: AuthorizationRef?

        // Pokus o autorizaci
        let status = AuthorizationCreate(&emptyRights,
                                         &environment,
                                         [.extendRights, .preAuthorize],
                                         &authRef)

        if let authRef = authRef {
            AuthorizationFree(authRef, [])
        }

        return status == errAuthorizationSuccess
    }
    
    func availableSerialPorts() -> [String] {
        let fileManager = FileManager.default
        do {
            let devContents = try fileManager.contentsOfDirectory(atPath: "/dev")
            let cuPorts = devContents.filter { $0.hasPrefix("cu.") }
            return cuPorts.sorted()
        } catch {
            print("❌ Chyba při čtení /dev: \(error)")
            return []
        }
    }
    
    func testATPort(_ port: String) -> (success: Bool, message: String) {
        let fullPortPath = port.hasPrefix("/dev/") ? port : "/dev/\(port)"
        
        // Kontrola existence portu
        guard FileManager.default.fileExists(atPath: fullPortPath) else {
            return (false, "Port neexistuje")
        }
        
        // Pokus o otevření portu
        let fd = Darwin.open(fullPortPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            return (false, "Nelze otevřít port")
        }
        
        defer {
            Darwin.close(fd)
        }
        
        // Nastavení sériového portu
        var options = termios()
        tcgetattr(fd, &options)
        cfmakeraw(&options)
        cfsetspeed(&options, speed_t(B115200))
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cc.16 /* VMIN */ = 0
        options.c_cc.17 /* VTIME */ = 1
        tcsetattr(fd, TCSANOW, &options)
        
        // Odeslání AT příkazu
        let command = "AT\r"
        _ = command.withCString {
            write(fd, $0, strlen($0))
        }
        
        // Čtení odpovědi
        var buffer = [UInt8](repeating: 0, count: 256)
        let start = Date()
        var result = ""
        
        repeat {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                if let part = String(bytes: buffer[0..<count], encoding: .utf8) {
                    result += part
                }
            } else {
                usleep(100_000) // 100ms
            }
        } while Date().timeIntervalSince(start) < 2.0 // 2 sekundy timeout
        
        // Vyhodnocení odpovědi
        let cleanResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanResult.contains("OK") {
            return (true, "AT port odpovídá správně")
        } else if cleanResult.isEmpty {
            return (false, "Žádná odpověď z portu")
        } else {
            return (false, "Neočekávaná odpověď: \(cleanResult)")
        }
    }
    
    func testPPPPort(_ port: String) -> (success: Bool, message: String) {
        let fullPortPath = port.hasPrefix("/dev/") ? port : "/dev/\(port)"
        
        // Kontrola existence portu
        guard FileManager.default.fileExists(atPath: fullPortPath) else {
            return (false, "Port neexistuje")
        }
        
        // Pro PPP port stačí kontrola existence a přístupnosti
        let fd = Darwin.open(fullPortPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            return (false, "Nelze otevřít port")
        }
        
        Darwin.close(fd)
        return (true, "PPP port je dostupný")
    }
}
