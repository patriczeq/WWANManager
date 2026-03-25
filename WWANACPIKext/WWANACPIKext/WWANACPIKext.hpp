#ifndef WWANACPIKext_hpp
#define WWANACPIKext_hpp

#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <IOKit/pci/IOPCIDevice.h>

// Selectors (must match WWANACPIHelper.h)
enum {
    kWWANSelectorModemOn    = 0,
    kWWANSelectorModemOff   = 1,
    kWWANSelectorReset      = 2,
    kWWANSelectorUSBMode    = 3,
    kWWANSelectorDetectMode = 4,
    kWWANSelectorCount      = 5
};

enum WWANMode {
    kWWANModePCIe    = 0,
    kWWANModeUSB     = 1,
    kWWANModeOff     = 2,
    kWWANModeUnknown = 3
};

// DSDT RP07 PXCS field offsets (used by modemOff/detectMode)
static const UInt32 kRP07_PXCS_E2  = 0xE2;   // L23E=bit2, L23R=bit3
static const UInt32 kRP07_PXCS_E0  = 0xE0;   // NCB7=bit7
static const UInt32 kRP07_PXCS_420 = 0x420;  // DPGE=bit30
static const UInt32 kRP07_PXCS_5A  = 0x5A;   // LASX=bit6


class WWANACPIKext : public IOService
{
    OSDeclareDefaultStructors(WWANACPIKext)

public:
    virtual bool       init(OSDictionary *dictionary = 0) override;
    virtual void       free(void) override;
    virtual IOService* probe(IOService *provider, SInt32 *score) override;
    virtual bool       start(IOService *provider) override;
    virtual void       stop(IOService *provider) override;

    IOReturn modemOn();
    IOReturn modemOff();
    IOReturn modemReset();
    IOReturn switchUSBMode();
    IOReturn detectMode(uint64_t *outMode);

private:
    IOACPIPlatformDevice* fACPIDevice;      // RP07 in ACPI plane (fromPath)
    IOService*            fPlatformExpert;  // IOACPIPlatformExpert — for absolute path _RST
    IOPCIDevice*          fPCIDevice;       // RP07 nub in IOService plane
    IOACPIPlatformDevice* fPXSXDevice;      // PXSX ACPI device for _RST

    IOPCIDevice*          findPCIDevice();
    IOACPIPlatformDevice* findPXSXDevice();

    void     pciSetBit(UInt32 offset, UInt8 bit, bool value);
    bool     pciGetBit(UInt32 offset, UInt8 bit);
    IOReturn callPXSX_RST();
};

class WWANACPIUserClient : public IOUserClient
{
    OSDeclareDefaultStructors(WWANACPIUserClient)

public:
    virtual bool     initWithTask(task_t owningTask, void *securityToken, UInt32 type) override;
    virtual bool     start(IOService *provider) override;
    virtual IOReturn clientClose(void) override;
    virtual IOReturn clientDied(void) override;
    virtual IOReturn externalMethod(uint32_t selector,
                                    IOExternalMethodArguments *arguments,
                                    IOExternalMethodDispatch *dispatch,
                                    OSObject *target,
                                    void *reference) override;
protected:
    WWANACPIKext* fProvider;
    task_t        fClientTask;
};

// Global singleton — set in start()
extern WWANACPIKext* gWWANKext;

#endif /* WWANACPIKext_hpp */
