# WWANManager

WWANManager is an alternative tool for managing WWAN (Mobile Broadband) connections on newer versions of macOS what missing WWAN config UI. This application was created primarily for use with the Fibocom L850GL modem, but may be compatible with similar devices that operate in USB mode and present ACM interfaces.

## Features

- Provides an alternative to native macOS WWAN connection management, ideal for systems where built-in support is missing or broken.
- Designed specifically for the Fibocom L850GL modem, which must be **unlocked** and **restarted in USB mode** using the command:  
  ```
  AT+GTUSBMODE=7
  ```
  This operation creates three ACM (serial) interfaces:
  - **One interface for AT diagnostic commands**
  - **One interface for the PPP (Point-to-Point Protocol) process**
- The app communicates with `pppd` (the PPP Daemon) via `sudo` and `osascript`, allowing it to establish and manage mobile broadband connections.

## Requirements

- **macOS** (older versions, where native WWAN support is insufficient or unavailable)
- **Fibocom L850GL modem** (other modems with similar interface and AT command sets may also work)
- The modem must be unlocked and rebooted into USB ACM mode (see above)
- `pppd` must be installed and accessible on your system
- Administrative privileges (uses `sudo` and `osascript` for process management)

## Usage

1. **Unlock and switch modem to USB mode:**
   - Connect to the modem's serial port and send:  
     ```
     AT+GTUSBMODE=7
     ```
   - The modem will reset and create three ACM interfaces on your Mac.

2. **Configure and run WWANManager:**
   - Launch the app.
   - Select the appropriate serial device for both AT commands and PPP connections.
   - Enter your carrier's APN and other connection details as needed.
   - Initiate the connection through the app interface.

3. **Troubleshooting:**
   - Ensure the modem is properly unlocked and in the correct mode.
   - Verify that you have the necessary permissions to run `pppd` via `sudo`.
   - Use the app's logs to debug any connection issues.

## Disclaimer

- This tool is intended for advanced users comfortable with command-line operations and macOS system internals.
- Use at your own risk. Modifying modem firmware or issuing incorrect AT commands can cause permanent device changes or loss of functionality.

## License

[MIT](LICENSE)

## Credits

Created and maintained by [patriczeq](https://github.com/patriczeq).