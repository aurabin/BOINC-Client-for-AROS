#include <aros/libcall.h>
#include <exec/libraries.h>
#include <hidd/pci.h>
#include <oop/oop.h>
#include <proto/exec.h>
#include <proto/oop.h>
#include <utility/hooks.h>
#include <stdio.h>
#include <string.h>

struct Library *OOPBase;
#undef HiddPCIDeviceAttrBase
static OOP_AttrBase HiddPCIDeviceAttrBase;

struct ScanState {
    int autocode;
    unsigned scanned;
    unsigned unknown;
};

static const char *candidate(unsigned vendor, unsigned product)
{
    if (vendor == 0x10ec &&
        (product == 0x8129 || product == 0x8138 || product == 0x8139))
        return "rtl8139.device";
    return NULL;
}

AROS_UFH3(IPTR, scan_device,
    AROS_UFHA(struct Hook *, hook, A0),
    AROS_UFHA(OOP_Object *, device, A2),
    AROS_UFHA(APTR, message, A1))
{
    AROS_USERFUNC_INIT
    struct ScanState *scan = hook->h_Data;
    IPTR vendor = 0xffff, product = 0xffff, revision = 0;
    const char *driver;

    (void)message;
    OOP_GetAttr(device, aHidd_PCIDevice_VendorID, &vendor);
    OOP_GetAttr(device, aHidd_PCIDevice_ProductID, &product);
    OOP_GetAttr(device, aHidd_PCIDevice_RevisionID, &revision);
    if (vendor == 0xffff || product == 0xffff)
        return 0;

    driver = candidate((unsigned)vendor, (unsigned)product);
    scan->scanned++;
    if (!driver) scan->unknown++;
    if (!scan->autocode) {
        printf("%04x,%04x,%02x,%s\n", (unsigned)vendor, (unsigned)product,
               (unsigned)revision, driver ? driver : "unmapped");
    } else if (!driver) {
        printf("    { 0x%04x, 0x%04x, 0x%02x },\n",
               (unsigned)vendor, (unsigned)product, (unsigned)revision);
    }
    return 0;
    AROS_USERFUNC_EXIT
}

int main(int argc, char **argv)
{
    struct ScanState scan = {0, 0, 0};
    struct Hook hook = {0};
    OOP_Object *pci;

    scan.autocode = argc == 2 && strcmp(argv[1], "--autocode") == 0;
    if (argc > 2 || (argc == 2 && !scan.autocode)) {
        fputs("Usage: DriverScan [--autocode]\n", stderr);
        return 20;
    }

    OOPBase = OpenLibrary("oop.library", 0);
    if (!OOPBase) {
        fputs("DriverScan: oop.library unavailable.\n", stderr);
        return 20;
    }
    HiddPCIDeviceAttrBase = OOP_ObtainAttrBase(IID_Hidd_PCIDevice);
    pci = HiddPCIDeviceAttrBase ? OOP_NewObject(NULL, CLID_Hidd_PCI, NULL) : NULL;
    if (!pci) {
        fputs("DriverScan: PCI HIDD unavailable.\n", stderr);
        if (HiddPCIDeviceAttrBase) OOP_ReleaseAttrBase(IID_Hidd_PCIDevice);
        CloseLibrary(OOPBase);
        return 20;
    }

    if (scan.autocode) {
        puts("/* Generated PCI match table. Verify IDs against device documentation.");
        puts(" * This file does not probe registers, bind a driver, or perform hardware I/O. */");
        puts("#include <stdint.h>");
        puts("struct DriverMatch { uint16_t vendor, product; uint8_t revision; };");
        puts("const struct DriverMatch unresolved_pci_devices[] = {");
    } else {
        puts("vendor,product,revision,candidate_driver");
    }
    hook.h_Entry = (IPTR (*)())scan_device;
    hook.h_Data = &scan;
    HIDD_PCI_EnumDevices(pci, &hook, NULL);
    if (scan.autocode) {
        puts("    { 0, 0, 0 } /* End of table */");
        puts("};");
    }
    fprintf(stderr, "DriverScan: %u PCI functions, %u without a known candidate.\n",
            scan.scanned, scan.unknown);

    OOP_DisposeObject(pci);
    OOP_ReleaseAttrBase(IID_Hidd_PCIDevice);
    CloseLibrary(OOPBase);
    return 0;
}
