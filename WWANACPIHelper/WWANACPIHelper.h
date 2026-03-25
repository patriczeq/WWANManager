#ifndef WWANACPIHelper_h
#define WWANACPIHelper_h

#include <IOKit/IOKitLib.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Selectors — must match kWWANSelector* in WWANACPIKext.hpp
#define kWWANHelperModemOn    0
#define kWWANHelperModemOff   1
#define kWWANHelperReset      2
#define kWWANHelperUSBMode    3
#define kWWANHelperDetectMode 4

typedef enum {
    kWWANACPISuccess          =  0,
    kWWANACPIErrorNotFound    = -1,
    kWWANACPIErrorConnection  = -2,
    kWWANACPIErrorExecution   = -3,
} WWANACPIResult;

typedef enum {
    kWWANModePCIe    = 0,
    kWWANModeUSB     = 1,
    kWWANModeOff     = 2,
    kWWANModeUnknown = 3,
} WWANMode;

// Connection management
WWANACPIResult WWANACPIHelper_Connect(void);
void           WWANACPIHelper_Disconnect(void);

// Operations
WWANACPIResult WWANACPIHelper_ModemOn(void);
WWANACPIResult WWANACPIHelper_ModemOff(void);
WWANACPIResult WWANACPIHelper_Reset(void);
WWANACPIResult WWANACPIHelper_SwitchUSBMode(void);
WWANACPIResult WWANACPIHelper_DetectMode(WWANMode *outMode);

// Legacy
WWANACPIResult WWANACPIHelper_WakeWWAN(void);

#ifdef __cplusplus
}
#endif

#endif /* WWANACPIHelper_h */
