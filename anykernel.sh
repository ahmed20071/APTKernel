# ================================================================
# APTKernel — AnyKernel3 Config
# Poco F3 / POCO X3 Pro — alioth / vayu
# ================================================================

# AnyKernel3 options
properties() { '
kernel.string=APTKernel by ApartTUSITU for Poco F3
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=alioth
device.name2=alioth
device.name3=aliothin
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
'; }

# ================================================================
# VARIANT — set by GitHub Actions (AOSP or HyperOS)
# ================================================================
VARIANT=AOSP

# ================================================================
# AnyKernel setup
# ================================================================
. tools/ak3-core.sh

# ── Backup & Flash ──────────────────────────────────────────────
dump_boot

# Flash kernel Image
write_boot

# ── DTBO (if present) ───────────────────────────────────────────
if [ -f "$ZIPFILE_DIR/dtbo.img" ]; then
    ui_print "- Flashing DTBO..."
    flash_dtbo
fi

# ── Post-flash messages ─────────────────────────────────────────
ui_print " "
ui_print "================================"
ui_print "    APTKernel — alioth"
ui_print "================================"
ui_print "  Variant : $VARIANT"
ui_print "================================"
ui_print " "
