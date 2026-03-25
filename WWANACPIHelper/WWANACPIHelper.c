#include "WWANACPIHelper.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <stdio.h>
#include <unistd.h>

static io_connect_t g_connection = IO_OBJECT_NULL;
static io_service_t g_service    = IO_OBJECT_NULL;

WWANACPIResult WWANACPIHelper_Connect(void)
{
    if (g_connection != IO_OBJECT_NULL) return kWWANACPISuccess;

    // Primary: match by IOClass name (set in Info.plist IOClass = WWANACPIKext)
    g_service = IOServiceGetMatchingService(kIOMasterPortDefault,
                                            IOServiceMatching("WWANACPIKext"));
    if (g_service != IO_OBJECT_NULL) {
        io_name_t n; IORegistryEntryGetName(g_service, n);
        printf("WWANACPIHelper: found via IOClass: %s\n", n);
    }

    // Fallback 1: match by property WWANACPIKextReady=true
    if (g_service == IO_OBJECT_NULL) {
        CFMutableDictionaryRef m = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (m) {
            CFMutableDictionaryRef pd = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            if (pd) {
                CFDictionarySetValue(pd, CFSTR("WWANACPIKextReady"), kCFBooleanTrue);
                CFDictionarySetValue(m, CFSTR("IOPropertyMatch"), pd);
                CFRelease(pd);
                // No IOClass restriction — search all IOService subclasses
                CFDictionarySetValue(m, CFSTR("IOProviderClass"), CFSTR("IOResources"));
            }
            g_service = IOServiceGetMatchingService(kIOMasterPortDefault, m);
            if (g_service != IO_OBJECT_NULL) {
                io_name_t n; IORegistryEntryGetName(g_service, n);
                printf("WWANACPIHelper: found via property match: %s\n", n);
            }
        }
    }

    // Fallback 2: iterate all IOService and find WWANACPIKextReady
    if (g_service == IO_OBJECT_NULL) {
        io_iterator_t iter = IO_OBJECT_NULL;
        IOServiceGetMatchingServices(kIOMasterPortDefault,
            IOServiceMatching("IOService"), &iter);
        if (iter != IO_OBJECT_NULL) {
            io_service_t s;
            while ((s = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
                CFTypeRef prop = IORegistryEntryCreateCFProperty(s,
                    CFSTR("WWANACPIKextReady"), kCFAllocatorDefault, 0);
                if (prop) {
                    CFRelease(prop);
                    g_service = s;
                    io_name_t n; IORegistryEntryGetName(g_service, n);
                    printf("WWANACPIHelper: found via iteration: %s\n", n);
                    break;
                }
                IOObjectRelease(s);
            }
            IOObjectRelease(iter);
        }
    }

    if (g_service == IO_OBJECT_NULL) {
        printf("WWANACPIHelper: kext not found\n");
        return kWWANACPIErrorNotFound;
    }

    kern_return_t kr = IOServiceOpen(g_service, mach_task_self(), 0, &g_connection);
    if (kr != KERN_SUCCESS) {
        printf("WWANACPIHelper: open failed: 0x%x\n", kr);
        IOObjectRelease(g_service); g_service = IO_OBJECT_NULL;
        return kWWANACPIErrorConnection;
    }
    printf("WWANACPIHelper: connected\n");
    return kWWANACPISuccess;
}

void WWANACPIHelper_Disconnect(void)
{
    if (g_connection != IO_OBJECT_NULL) { IOServiceClose(g_connection); g_connection = IO_OBJECT_NULL; }
    if (g_service    != IO_OBJECT_NULL) { IOObjectRelease(g_service);   g_service    = IO_OBJECT_NULL; }
}

static WWANACPIResult callSelector(uint32_t selector, uint64_t *scalarOut, uint32_t scalarOutCnt)
{
    WWANACPIResult r = WWANACPIHelper_Connect();
    if (r != kWWANACPISuccess) return r;

    uint32_t outCnt = scalarOutCnt;
    kern_return_t kr = IOConnectCallMethod(g_connection, selector,
                                           NULL, 0, NULL, 0,
                                           scalarOut, scalarOut ? &outCnt : NULL,
                                           NULL, NULL);
    if (kr != KERN_SUCCESS) {
        printf("WWANACPIHelper: selector %u failed: 0x%x\n", selector, kr);
        return kWWANACPIErrorExecution;
    }
    return kWWANACPISuccess;
}

WWANACPIResult WWANACPIHelper_ModemOn(void)
{
    printf("WWANACPIHelper: ModemOn\n");
    return callSelector(kWWANHelperModemOn, NULL, 0);
}

WWANACPIResult WWANACPIHelper_ModemOff(void)
{
    printf("WWANACPIHelper: ModemOff\n");
    return callSelector(kWWANHelperModemOff, NULL, 0);
}

WWANACPIResult WWANACPIHelper_Reset(void)
{
    printf("WWANACPIHelper: Reset\n");
    return callSelector(kWWANHelperReset, NULL, 0);
}

WWANACPIResult WWANACPIHelper_SwitchUSBMode(void)
{
    printf("WWANACPIHelper: SwitchUSBMode\n");
    return callSelector(kWWANHelperUSBMode, NULL, 0);
}

WWANACPIResult WWANACPIHelper_DetectMode(WWANMode *outMode)
{
    printf("WWANACPIHelper: DetectMode\n");
    uint64_t mode = kWWANModeUnknown;
    uint32_t cnt  = 1;
    WWANACPIResult r = WWANACPIHelper_Connect();
    if (r != kWWANACPISuccess) return r;

    kern_return_t kr = IOConnectCallMethod(g_connection, kWWANHelperDetectMode,
                                           NULL, 0, NULL, 0,
                                           &mode, &cnt, NULL, NULL);
    if (kr != KERN_SUCCESS) {
        printf("WWANACPIHelper: DetectMode failed: 0x%x\n", kr);
        return kWWANACPIErrorExecution;
    }
    if (outMode) *outMode = (WWANMode)mode;
    printf("WWANACPIHelper: mode = %llu\n", mode);
    return kWWANACPISuccess;
}

// Legacy — maps to ModemOn (PINI wake sequence)
WWANACPIResult WWANACPIHelper_WakeWWAN(void)
{
    printf("WWANACPIHelper: WakeWWAN -> ModemOn\n");
    return WWANACPIHelper_ModemOn();
}
