#include "WWANACPIKext.hpp"
#include <IOKit/IOLib.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <IOKit/pci/IOPCIDevice.h>

// Global singleton
WWANACPIKext* gWWANKext = NULL;

// Kernel-safe strstr replacement
static inline const char* k_strstr(const char* haystack, const char* needle) {
    if (!haystack || !needle) return NULL;
    size_t nlen = strlen(needle);
    if (nlen == 0) return haystack;
    for (; *haystack; haystack++) {
        if (strncmp(haystack, needle, nlen) == 0) return haystack;
    }
    return NULL;
}

// ============================================================
// WWANACPIKext — IOService
//
// Implements 5 operations replicating SSDT-WWAN / DSDT behaviour:
//
//  modemOn / switchUSBMode:
//    Replicates SSDT-WWAN PINI:
//      PCI_Config[0x50] = 0x0052   (OperationRegion AAAA, Field BBBB)
//      Sleep(16)
//      PXSX._RST()
//
//  modemOff:
//    Replicates DSDT DL23:
//      L23E (PXCS[0xE2] bit2) = 1  -> triggers D0->L2/L3 transition
//      wait up to 50ms for L23E to clear (HW ack)
//      NCB7 (PXCS[0xE0] bit7) = 1
//
//  modemReset:
//    modemOff() -> IOSleep(500) -> modemOn()
//
//  detectMode:
//    Read PCI config registers:
//      NCB7=1 && DPGE=0 -> Off/L2L3
//      PCI[0x50] & 0xFF == 0x52   -> USB mode
//      LASX=1                     -> PCIe active
// ============================================================

#define super IOService
OSDefineMetaClassAndStructors(WWANACPIKext, IOService)

// ============================================================
// init / free / probe / start / stop
// ============================================================

bool WWANACPIKext::init(OSDictionary *dict)
{
    if (!super::init(dict)) return false;
    fACPIDevice     = NULL;
    fPlatformExpert = NULL;
    fPCIDevice      = NULL;
    fPXSXDevice     = NULL;
    IOLog("WWANACPIKext: init\n");
    return true;
}

void WWANACPIKext::free(void)
{
    IOLog("WWANACPIKext: free\n");
    super::free();
}

IOService* WWANACPIKext::probe(IOService *provider, SInt32 *score)
{
    IOLog("WWANACPIKext: probe\n");
    return super::probe(provider, score);
}

bool WWANACPIKext::start(IOService *provider)
{
    if (!super::start(provider)) return false;
    IOLog("WWANACPIKext: start — provider: %s class: %s\n",
          provider->getName(), provider->getMetaClass()->getClassName());

    // Provider is IOResources — we must find all devices ourselves
    fACPIDevice     = NULL;
    fPlatformExpert = NULL;
    fPCIDevice      = NULL;
    fPXSXDevice     = NULL;

    // Find RP07 PCI device by acpi-path or location
    fPCIDevice = findPCIDevice();
    IOLog("WWANACPIKext: RP07 PCI: %s\n", fPCIDevice ? fPCIDevice->getName() : "NULL");

    // Find RP07 and PXSX in ACPI plane
    const IORegistryPlane* acpiPlane = IORegistryEntry::getPlane("IOACPIPlane");
    if (acpiPlane) {
        IORegistryEntry* rp07entry = IORegistryEntry::fromPath(
            "IOACPIPlane:/_SB/PCI0@0/RP07@1c0006", acpiPlane);
        if (rp07entry) {
            fACPIDevice = OSDynamicCast(IOACPIPlatformDevice, rp07entry);
            if (!fACPIDevice) rp07entry->release();
            IOLog("WWANACPIKext: RP07 ACPI: %s\n", fACPIDevice ? "OK" : "not IOACPIPlatformDevice");
        }
        IORegistryEntry* pxsxEntry = IORegistryEntry::fromPath(
            "IOACPIPlane:/_SB/PCI0@0/RP07@1c0006/PXSX@0", acpiPlane);
        if (pxsxEntry) {
            fPXSXDevice = OSDynamicCast(IOACPIPlatformDevice, pxsxEntry);
            if (!fPXSXDevice) {
                IOLog("WWANACPIKext: PXSX found but is %s not IOACPIPlatformDevice\n",
                      pxsxEntry->getMetaClass()->getClassName());
                pxsxEntry->release();
            } else {
                IOLog("WWANACPIKext: PXSX ACPI: OK\n");
            }
        } else {
            IOLog("WWANACPIKext: PXSX not found in ACPI plane\n");
        }
    }

    // Find IOACPIPlatformExpert for absolute path _RST call
    OSDictionary* expertMatch = IOService::serviceMatching("IOACPIPlatformExpert");
    if (expertMatch) {
        IOService* expert = IOService::waitForMatchingService(expertMatch, 3000000000ULL);
        expertMatch->release();
        if (expert) {
            fPlatformExpert = expert;
            IOLog("WWANACPIKext: IOACPIPlatformExpert: %s\n", expert->getName());
        }
    }

    IOLog("WWANACPIKext: ready — PCI:%s ACPI:%s PXSX:%s Expert:%s\n",
          fPCIDevice      ? "OK" : "NULL",
          fACPIDevice     ? "OK" : "NULL",
          fPXSXDevice     ? "OK" : "NULL",
          fPlatformExpert ? "OK" : "NULL");

    // Set global singleton and register service
    gWWANKext = this;
    setProperty("WWANACPIKextReady", kOSBooleanTrue);
    registerService();
    IOLog("WWANACPIKext: registerService() called — service is now discoverable\n");
    return true;
}

void WWANACPIKext::stop(IOService *provider)
{
    IOLog("WWANACPIKext: stop\n");
    OSSafeReleaseNULL(fACPIDevice);
    OSSafeReleaseNULL(fPCIDevice);
    OSSafeReleaseNULL(fPXSXDevice);
    fPlatformExpert = NULL;
    super::stop(provider);
}

// ============================================================
// Device discovery — PCI and PXSX only (ACPI = provider)
// ============================================================

IOPCIDevice* WWANACPIKext::findPCIDevice()
{
    // RP07 is IOPCIDevice in IODeviceTree at location "1C,6"
    // acpi-path property = "IOACPIPlane:/_SB/PCI0@0/RP07@1c0006"
    // Try direct lookup via acpi-path property first
    OSDictionary* propMatch = IOService::serviceMatching("IOPCIDevice");
    if (!propMatch) return NULL;

    OSIterator* iter = IOService::getMatchingServices(propMatch);
    propMatch->release();
    if (!iter) return NULL;

    IOPCIDevice* found = NULL;
    IORegistryEntry* candidate;
    while ((candidate = OSDynamicCast(IORegistryEntry, iter->getNextObject())) != NULL) {
        IOPCIDevice* pci = OSDynamicCast(IOPCIDevice, candidate);
        if (!pci) continue;

        // Match by acpi-path property (most reliable)
        OSObject* pathProp = pci->getProperty("acpi-path");
        if (pathProp) {
            OSString* pathStr = OSDynamicCast(OSString, pathProp);
            if (pathStr) {
                const char* path = pathStr->getCStringNoCopy();
                if (path && k_strstr(path, "RP07@1c0006")) {
                    pci->retain();
                    found = pci;
                    IOLog("WWANACPIKext: PCI RP07 found via acpi-path: %s\n", path);
                    break;
                }
            }
        }

        // Fallback: match by location "1C,6" or "1c,6"
        const char* loc = pci->getLocation();
        if (loc) {
            // Case-insensitive compare for hex location
            if (strncmp(loc, "1c,6", 4) == 0 || strncmp(loc, "1C,6", 4) == 0) {
                pci->retain();
                found = pci;
                IOLog("WWANACPIKext: PCI RP07 found via location: %s\n", loc);
                break;
            }
        }
    }
    iter->release();
    if (!found) IOLog("WWANACPIKext: PCI RP07 not found\n");
    return found;
}

IOACPIPlatformDevice* WWANACPIKext::findPXSXDevice()
{
    // PXSX is IOPCIDevice in IODeviceTree (not IOACPIPlatformDevice)
    // We don't need PXSX as IOACPIPlatformDevice — we call _RST via fACPIDevice
    // Just log what PXSX is for diagnostics
    if (fACPIDevice) {
        const IORegistryPlane* acpiPlane = IORegistryEntry::getPlane("IOACPIPlane");
        if (acpiPlane) {
            OSIterator* iter = fACPIDevice->getChildIterator(acpiPlane);
            if (iter) {
                IORegistryEntry* c;
                while ((c = OSDynamicCast(IORegistryEntry, iter->getNextObject())) != NULL) {
                    const char* n = c->getName(acpiPlane);
                    IOLog("WWANACPIKext: RP07 ACPI child: %s (class: %s)\n",
                          n ? n : "?", c->getMetaClass()->getClassName());
                }
                iter->release();
            }
        }
    }
    IOLog("WWANACPIKext: PXSX._RST will be called via RP07 ACPI evaluateObject\n");
    return NULL; // Not used directly
}

// ============================================================
// Low-level PCI config bit helpers
// ============================================================

void WWANACPIKext::pciSetBit(UInt32 offset, UInt8 bit, bool value)
{
    if (!fPCIDevice) return;
    // Read 32-bit aligned register
    UInt32 aligned = offset & ~0x3U;
    // bit position within the 32-bit register
    UInt8 byteShift = (UInt8)((offset & 0x3U) * 8);
    UInt8 totalBit  = byteShift + bit;
    UInt32 reg = fPCIDevice->configRead32((UInt32)aligned);
    IOLog("WWANACPIKext: pciSetBit offset=0x%x bit=%d val=%d reg32[0x%x]=0x%08x\n",
          offset, bit, value, aligned, reg);
    if (value) reg |=  (1U << totalBit);
    else       reg &= ~(1U << totalBit);
    fPCIDevice->configWrite32((UInt32)aligned, reg);
}

bool WWANACPIKext::pciGetBit(UInt32 offset, UInt8 bit)
{
    if (!fPCIDevice) return false;
    UInt32 aligned = offset & ~0x3U;
    UInt8 byteShift = (UInt8)((offset & 0x3U) * 8);
    UInt8 totalBit  = byteShift + bit;
    UInt32 reg = fPCIDevice->configRead32((UInt32)aligned);
    return (reg >> totalBit) & 1U;
}

// ============================================================
// PXSX._RST via evaluateObject or callPlatformFunction fallback
// ============================================================

IOReturn WWANACPIKext::callPXSX_RST()
{
    IOLog("WWANACPIKext: callPXSX_RST\n");

    // Method 1: PXSX._RST via fPXSXDevice (direct ACPI device — best option)
    if (fPXSXDevice) {
        IOReturn r = fPXSXDevice->evaluateObject("_RST");
        IOLog("WWANACPIKext: fPXSXDevice->_RST = 0x%x %s\n", r, r==kIOReturnSuccess?"OK":"FAIL");
        if (r == kIOReturnSuccess) return r;
    }

    // Method 2: absolute path via IOACPIPlatformExpert
    if (fPlatformExpert) {
        // IOACPIPlatformExpert inherits from IOACPIPlatformDevice — try evaluateObject
        IOACPIPlatformDevice* acpiExpert = OSDynamicCast(IOACPIPlatformDevice, fPlatformExpert);
        if (acpiExpert) {
            IOReturn r = acpiExpert->evaluateObject("\\_SB.PCI0.RP07.PXSX._RST");
            IOLog("WWANACPIKext: expert->_RST absolute = 0x%x %s\n", r, r==kIOReturnSuccess?"OK":"FAIL");
            if (r == kIOReturnSuccess) return r;
        }
    }

    // Method 3: via RP07 ACPI device (relative path)
    if (fACPIDevice) {
        IOReturn r = fACPIDevice->evaluateObject("PXSX._RST");
        IOLog("WWANACPIKext: fACPIDevice->PXSX._RST = 0x%x %s\n", r, r==kIOReturnSuccess?"OK":"FAIL");
        if (r == kIOReturnSuccess) return r;
    }

    // Method 4: SBR via Bridge Control register — hardware reset of PCIe slot
    // Equivalent to asserting RST# pin on the M.2 slot
    if (fPCIDevice) {
        IOLog("WWANACPIKext: SBR via Bridge Control (fallback)\n");
        UInt16 bc = fPCIDevice->configRead16((UInt32)0x3E);
        IOLog("WWANACPIKext: BridgeCtrl before=0x%04x\n", bc);
        fPCIDevice->configWrite16((UInt32)0x3E, (UInt16)(bc | 0x0040));  // Assert SBR
        IOSleep(100);
        fPCIDevice->configWrite16((UInt32)0x3E, (UInt16)(bc & ~0x0040U)); // Deassert SBR
        IOSleep(100);
        IOLog("WWANACPIKext: SBR done BridgeCtrl after=0x%04x\n",
              fPCIDevice->configRead16((UInt32)0x3E));
        return kIOReturnSuccess;
    }

    IOLog("WWANACPIKext: callPXSX_RST — ALL methods failed\n");
    return kIOReturnNotFound;
}

// ============================================================
// modemOn / switchUSBMode
// Exact replica of xmm7360-usb-modeswitch / SSDT-WWAN PINI:
//   setpci -s RP07 CAP_EXP+10.w=0052
//     = write 0x0052 to Link Control Register (PCIe cap offset + 0x10)
//   Sleep(16ms)
//   PXSX._RST  (= callPXSX_RST = SBR on bridge)
// ============================================================

IOReturn WWANACPIKext::modemOn()
{
    IOLog("WWANACPIKext: modemOn — SSDT PINI replica (PCI[0x50]=0x0052 + PXSX._RST)\n");

    // Lazy re-find PCI device
    if (!fPCIDevice) {
        fPCIDevice = findPCIDevice();
    }
    if (!fPCIDevice) {
        IOLog("WWANACPIKext: modemOn — no PCI device (RP07)\n");
        return kIOReturnNotFound;
    }

    // === Exact replica of HeySora SSDT PINI / xmm7360-usb-modeswitch ===
    //
    // SSDT does:
    //   OperationRegion (AAAA, PCI_Config, 0x50, 0x02)
    //   Field BBBB, 16 bits
    //   BBBB = 0x52        <- write 0x0052 to PCI_Config offset 0x50
    //   Sleep(0x10)        <- 16ms
    //   PXSX._RST()        <- reset the slot
    //
    // Linux xmm2usb does:
    //   setpci -s RP07 CAP_EXP+10.w=0052   <- same register (CAP_EXP+0x10 = 0x50 on this hw)
    //   acpi_call PXSX._RST

    // Step 1: Read current value at 0x50 for logging
    UInt16 before = fPCIDevice->configRead16((UInt32)0x50);
    IOLog("WWANACPIKext: PCI[0x50] before = 0x%04x\n", before);

    // Step 2: Write 0x0052 to PCI_Config offset 0x50 (Field BBBB = 0x52)
    fPCIDevice->configWrite16((UInt32)0x50, (UInt16)0x0052);
    UInt16 after = fPCIDevice->configRead16((UInt32)0x50);
    IOLog("WWANACPIKext: PCI[0x50] written 0x0052 — readback=0x%04x\n", after);

    // Step 3: Sleep 16ms (SSDT: Sleep(0x10))
    IOSleep(16);

    // Step 4: PXSX._RST — reset the PCIe slot
    IOReturn ret = callPXSX_RST();
    IOLog("WWANACPIKext: PXSX._RST result=0x%x %s\n", ret, ret==kIOReturnSuccess?"OK":"FAIL");

    IOLog("WWANACPIKext: modemOn done — modem will enumerate on USB in ~5-10s\n");
    return kIOReturnSuccess;
}

IOReturn WWANACPIKext::switchUSBMode()
{
    IOLog("WWANACPIKext: switchUSBMode\n");
    return modemOn();
}

// ============================================================
// modemOff
// Exact replica of DSDT DL23:
//   L23E = 1       -> PXCS[0xE2] bit2 = 1
//   wait for L23E==0 (HW clears it, up to 50ms)
//   NCB7 = 1       -> PXCS[0xE0] bit7 = 1
// ============================================================

IOReturn WWANACPIKext::modemOff()
{
    IOLog("WWANACPIKext: modemOff\n");
    if (!fPCIDevice) {
        IOLog("WWANACPIKext: modemOff failed — no PCI device\n");
        return kIOReturnNotFound;
    }

    // First detect current mode
    uint64_t currentMode = kWWANModeUnknown;
    detectMode(&currentMode);

    if (currentMode == kWWANModeOff) {
        IOLog("WWANACPIKext: modemOff — already Off\n");
        return kIOReturnSuccess;
    }

    if (currentMode == kWWANModeUSB) {
        // Modem is in USB mode — PCIe link is already down (LASX=0)
        // DL23 sequence requires active PCIe link — won't work here
        // To sleep from USB mode: we need to power cycle via PXSX._RST
        // which will drop the USB device and then we can set NCB7
        IOLog("WWANACPIKext: modemOff from USB mode — calling _RST first\n");
        callPXSX_RST();
        IOSleep(200);
        // Now set NCB7 to keep it in L2/L3
        pciSetBit(kRP07_PXCS_E0, 7, true);
        IOLog("WWANACPIKext: NCB7 set — modemOff (USB→Off) done\n");
        return kIOReturnSuccess;
    }

    // PCIe mode — use standard DL23 sequence from DSDT:
    //   L23E = 1  → triggers D0→L2/L3 transition
    //   wait for L23E==0 (HW clears it, up to 50ms)
    //   NCB7 = 1
    IOLog("WWANACPIKext: modemOff from PCIe mode — DL23 sequence\n");

    // DPGE = 0 first (from DSDT L23D — but DL23 doesn't do this)
    // Just do what DSDT DL23 does:
    // L23E = 1  (PXCS offset 0xE2, bit 2)
    pciSetBit(kRP07_PXCS_E2, 2, true);
    IOLog("WWANACPIKext: L23E set\n");

    // Wait up to 80ms for L23E to be cleared by HW (8 x 10ms)
    for (int i = 0; i < 8; i++) {
        IOSleep(10);
        if (!pciGetBit(kRP07_PXCS_E2, 2)) {
            IOLog("WWANACPIKext: L23E cleared after %dms\n", (i + 1) * 10);
            break;
        }
    }

    // NCB7 = 1  (PXCS offset 0xE0, bit 7)
    pciSetBit(kRP07_PXCS_E0, 7, true);
    IOLog("WWANACPIKext: NCB7 set — modemOff (PCIe→Off) done\n");
    return kIOReturnSuccess;
}

// ============================================================
// modemReset — OFF -> 500ms -> ON
// ============================================================

IOReturn WWANACPIKext::modemReset()
{
    IOLog("WWANACPIKext: modemReset\n");
    IOReturn ret = modemOff();
    IOLog("WWANACPIKext: modemReset — off done (0x%x), sleeping 500ms\n", ret);
    IOSleep(500);
    ret = modemOn();
    IOLog("WWANACPIKext: modemReset — on done (0x%x)\n", ret);
    return ret;
}

// ============================================================
// detectMode
// Reads PCI config registers to determine current state:
//   NCB7=1 && DPGE=0  -> Off (L2/L3)
//   PCI[0x50] low byte == 0x52  -> USB mode
//   LASX=1             -> PCIe active
// ============================================================

IOReturn WWANACPIKext::detectMode(uint64_t* outMode)
{
    if (!outMode) return kIOReturnBadArgument;
    *outMode = kWWANModeUnknown;

    if (!fPCIDevice) {
        // No PCI device at all — truly off / not enumerated
        IOLog("WWANACPIKext: detectMode — no PCI device\n");
        *outMode = kWWANModeOff;
        return kIOReturnSuccess;
    }

    // Read all relevant DSDT fields from PXCS OperationRegion
    // PXCS covers PCI_Config 0x00..0x0480
    //
    //  VDID  = [0x00] 32-bit — 0xFFFFFFFF = device absent
    //  LASX  = [0x52] bit 13 — PCIe link active (Data Link Layer Up)
    //  NCB7  = [0xE0] bit  7 — "No Clock to Bus" / L2L3 ready
    //  L23E  = [0xE2] bit  2 — L23 Enable (D0→L2/L3 in progress)
    //  L23R  = [0xE2] bit  3 — L23 Ready (L2/L3→D0 in progress)
    //  DPGE  = [0x420] bit 30 — DPHY PG enable

    UInt32 vdid = fPCIDevice->configRead32((UInt32)0x00);
    if (vdid == 0xFFFFFFFF) {
        // Device not present / config space not responding
        IOLog("WWANACPIKext: detectMode — VDID=0xFFFFFFFF device absent → Off\n");
        *outMode = kWWANModeOff;
        return kIOReturnSuccess;
    }

    UInt16 reg52  = fPCIDevice->configRead16((UInt32)0x52);
    UInt8  regE0  = (UInt8)(fPCIDevice->configRead32((UInt32)0xE0) >> 0);
    UInt8  regE2  = (UInt8)(fPCIDevice->configRead32((UInt32)0xE0) >> 16);
    UInt32 reg420 = fPCIDevice->configRead32((UInt32)0x420);
    UInt16 reg50  = fPCIDevice->configRead16((UInt32)0x50);

    bool lasx = (reg52  >> 13) & 1;   // PCIe Data Link Layer active
    bool ncb7 = (regE0  >>  7) & 1;   // No Clock / L2L3
    bool l23e = (regE2  >>  2) & 1;   // L23 Enable
    bool dpge = (reg420 >> 30) & 1;   // DPHY PG enable

    IOLog("WWANACPIKext: detectMode — VDID=0x%08x LASX=%d NCB7=%d L23E=%d DPGE=%d reg50=0x%04x reg52=0x%04x\n",
          vdid, lasx, ncb7, l23e, dpge, reg50, reg52);

    // Priority order:
    // 1. LASX=1 → PCIe link is up → modem in PCIe mode
    // 2. NCB7=1 → clock gated → modem in L2/L3 (Off/Sleep)
    // 3. LASX=0 + NCB7=0 + VDID valid → modem enumerated but no PCIe link → USB mode
    //    (after PINI/modemOn the modem drops off PCIe and comes up on USB)

    if (lasx) {
        *outMode = kWWANModePCIe;
        IOLog("WWANACPIKext: mode = PCIe (LASX=1)\n");
    } else if (ncb7) {
        *outMode = kWWANModeOff;
        IOLog("WWANACPIKext: mode = Off/Sleep (NCB7=1 LASX=0)\n");
    } else {
        // LASX=0, NCB7=0, VDID valid — modem is present but PCIe link is down
        // This happens in USB mode: modem dropped PCIe, now on USB bus
        *outMode = kWWANModeUSB;
        IOLog("WWANACPIKext: mode = USB (LASX=0 NCB7=0 VDID=0x%08x)\n", vdid);
    }
    return kIOReturnSuccess;
}

// ============================================================
// WWANACPIUserClient
// ============================================================
#undef super
#define super IOUserClient
OSDefineMetaClassAndStructors(WWANACPIUserClient, IOUserClient)

bool WWANACPIUserClient::initWithTask(task_t owningTask, void *securityToken, UInt32 type)
{
    if (!super::initWithTask(owningTask, securityToken, type)) return false;
    fClientTask = owningTask;
    fProvider   = NULL;
    return true;
}

bool WWANACPIUserClient::start(IOService *provider)
{
    if (!super::start(provider)) return false;
    fProvider = OSDynamicCast(WWANACPIKext, provider);
    if (!fProvider) {
        IOLog("WWANACPIUserClient: provider is not WWANACPIKext\n");
        return false;
    }
    IOLog("WWANACPIUserClient: started\n");
    return true;
}

IOReturn WWANACPIUserClient::clientClose(void)
{
    IOLog("WWANACPIUserClient: clientClose\n");
    fProvider = NULL;
    terminate();
    return kIOReturnSuccess;
}

IOReturn WWANACPIUserClient::clientDied(void)
{
    return clientClose();
}

IOReturn WWANACPIUserClient::externalMethod(uint32_t selector,
                                             IOExternalMethodArguments *arguments,
                                             IOExternalMethodDispatch *dispatch,
                                             OSObject *target,
                                             void *reference)
{
    if (!fProvider) {
        IOLog("WWANACPIUserClient: no provider\n");
        return kIOReturnNotReady;
    }

    switch (selector) {
        case kWWANSelectorModemOn:
            IOLog("WWANACPIUserClient: sel 0 modemOn\n");
            return fProvider->modemOn();

        case kWWANSelectorModemOff:
            IOLog("WWANACPIUserClient: sel 1 modemOff\n");
            return fProvider->modemOff();

        case kWWANSelectorReset:
            IOLog("WWANACPIUserClient: sel 2 modemReset\n");
            return fProvider->modemReset();

        case kWWANSelectorUSBMode:
            IOLog("WWANACPIUserClient: sel 3 switchUSBMode\n");
            return fProvider->switchUSBMode();

        case kWWANSelectorDetectMode: {
            IOLog("WWANACPIUserClient: sel 4 detectMode\n");
            uint64_t mode = kWWANModeUnknown;
            IOReturn ret = fProvider->detectMode(&mode);
            if (arguments && arguments->scalarOutputCount >= 1)
                arguments->scalarOutput[0] = mode;
            return ret;
        }

        default:
            IOLog("WWANACPIUserClient: unknown selector %u\n", selector);
            return kIOReturnBadArgument;
    }
}
