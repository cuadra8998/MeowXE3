/*
 * MeowXE3Boot: injected by OpenCore (boot kernel collection). It keeps macOS from putting its boot-display framebuffer
 * (IONDRVFramebuffer on IOBootNDRV, ".Display_boot") on the Intel GPU when MeowXE3 drives that GPU.
 *
 * Why: IONDRVFramebuffer::initForPM marks every power state of a boot-NDRV framebuffer kIOPMPreventSystemSleep (it
 * can only doze), so while .Display_boot exists the Mac never sleeps (dark wake, "System sleep preventers:
 * .Display_boot"). Removing it after it started panicked/froze earlier; this stops it from being created instead:
 * IONDRVFramebuffer::probe declines a device carrying "AAPL,iokit-ignore-ndrv" (IONDRVSupport.h, kIONDRVIgnoreKey).
 *
 * When: only if boot-args turn MeowXE3 on (nmxintel=1) and not -nvoff (OpenCore's "start once without driver"), so a
 * start without MeowXE3 keeps the boot display and has a desktop. It sets the property in probe and never attaches.
 */
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <pexpert/pexpert.h>
#include <mach/kmod.h>

/* the module header every kext with code needs (Xcode generates it; this build declares it, as MeowXE3AGDC does) */
extern "C" kern_return_t _start(kmod_info_t *ki, void *d);
extern "C" kern_return_t _stop(kmod_info_t *ki, void *d);
extern "C" { KMOD_EXPLICIT_DECL(com.meowxe3.MeowXE3Boot, "1.0.1", _start, _stop) }
extern "C" kern_return_t _start(kmod_info_t *ki, void *d) { return KERN_SUCCESS; }
extern "C" kern_return_t _stop(kmod_info_t *ki, void *d)  { return KERN_SUCCESS; }

class MeowXE3Boot : public IOService {
    OSDeclareDefaultStructors(MeowXE3Boot)
public:
    IOService *probe(IOService *provider, SInt32 *score) override;
};

OSDefineMetaClassAndStructors(MeowXE3Boot, IOService)

IOService *MeowXE3Boot::probe(IOService *provider, SInt32 *score)
{
    IOPCIDevice *pci = OSDynamicCast(IOPCIDevice, provider);
    if (pci == nullptr)
        return nullptr;
    int v = 0;
    if (PE_parse_boot_argn("-nvoff", &v, sizeof(v))) {
        IOLog("MeowXE3Boot: -nvoff: the boot display stays\n");
        return nullptr;
    }
    v = 0;
    if (!PE_parse_boot_argn("nmxintel", &v, sizeof(v)) || v == 0) {
        IOLog("MeowXE3Boot: nmxintel not set: the boot display stays\n");
        return nullptr;
    }
    provider->setProperty("AAPL,iokit-ignore-ndrv", kOSBooleanTrue);
    IOLog("MeowXE3Boot: %s: no boot-display framebuffer (it would keep the Mac from sleeping); MeowXE3 drives it\n",
          provider->getName());
    return nullptr;     /* never attaches: the property is all it does */
}
