import Foundation
import Security

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
}
