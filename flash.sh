#!/bin/sh
#
# Universal Firmware Flasher for Notion P298 (ASR1802S / PXA1826)
#
# Flashes either OpenWrt or Stock Linux firmware to Slot B using the
# universal hash-agnostic DTIM-B, active_slot='b', quiet=0, and NASR RSA bypass.
#
# Safe: strictly targets Slot B (mtd14, mtd16, mtd8, mtd19, mtd20, mtd21).
#       Never touches Slot A or factory calibration/NVRAM (mtd1..mtd6).
#
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS_DIR="$SCRIPT_DIR/tools"
SWDL="$TOOLS_DIR/swdl_linux"
TIMEOUT=600
TARGET=""

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    printf "${BOLD}Usage:${NC} %s <target> [options]\n\n" "$(basename "$0")"
    printf "${BOLD}Targets:${NC}\n"
    printf "  ${GREEN}openwrt${NC}              Flash OpenWrt Linux 6.18 kernel & SquashFS rootfs to Slot B\n"
    printf "  ${GREEN}stock${NC}                Restore clean factory stock Linux firmware to Slot B\n\n"
    printf "${BOLD}Options:${NC}\n"
    printf "  -t, --timeout <seconds>  USB download mode timeout in seconds (default: 600)\n"
    printf "  -h, --help               Display this comprehensive help guide\n\n"
    printf "${BOLD}Examples:${NC}\n"
    printf "  doas ./flash.sh openwrt\n"
    printf "  doas ./flash.sh stock\n"
    printf "  doas ./flash.sh openwrt --timeout 300\n\n"
    printf "${BOLD}Convenience Wrappers:${NC}\n"
    printf "  ./flash_openwrt.sh       Shortcut for './flash.sh openwrt'\n"
    printf "  ./flash_stock.sh         Shortcut for './flash.sh stock'\n\n"
    printf "${BOLD}Hardware Instructions:${NC}\n"
    printf "  1. Connect a USB data cable between the router and your computer.\n"
    printf "  2. Launch this flasher script with root privileges (doas / sudo).\n"
    printf "  3. Power on the router (or plug in the 12V power supply).\n"
    printf "  4. The flasher automatically handshakes with the ASR1802S bootloader\n"
    printf "     over USB Download Mode (USB ID 2ecc:3002) and writes all partitions.\n"
    printf "  5. Once completed, power-cycle the router normally to boot.\n\n"
    printf "${BOLD}Safety & Dual-Slot Architecture:${NC}\n"
    printf "  This flasher strictly programs Slot B (mtd14, mtd16, mtd8, mtd19, mtd20, mtd21).\n"
    printf "  It NEVER touches Slot A or factory calibration/IMEI/MAC data (mtd1..mtd6).\n"
    exit 0
}

# Parse help early before privilege check
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            ;;
    esac
done

# Root privilege check / auto-elevation
if [ "$(id -u)" -ne 0 ]; then
    if command -v doas >/dev/null 2>&1; then
        printf "${YELLOW}Privilege escalation required. Re-running with doas...${NC}\n"
        exec doas sh "$0" "$@"
    elif command -v sudo >/dev/null 2>&1; then
        printf "${YELLOW}Privilege escalation required. Re-running with sudo...${NC}\n"
        exec sudo sh "$0" "$@"
    else
        printf "${RED}Error: Root privileges required. Please run with doas or sudo.${NC}\n" >&2
        exit 1
    fi
fi

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        openwrt|--openwrt)
            TARGET="openwrt"
            shift
            ;;
        stock|--stock)
            TARGET="stock"
            shift
            ;;
        -t|--timeout)
            if [ $# -ge 2 ]; then
                TIMEOUT="$2"
                shift 2
            else
                printf "${RED}Error: --timeout requires a value in seconds.${NC}\n" >&2
                exit 1
            fi
            ;;
        -h|--help)
            usage
            ;;
        *)
            printf "${RED}Error: Unknown argument: %s${NC}\n\n" "$1" >&2
            usage
            ;;
    esac
done

# If no target specified, show interactive prompt if in terminal, or fail gracefully
if [ -z "$TARGET" ]; then
    if [ -t 0 ]; then
        printf "${CYAN}================================================================${NC}\n"
        printf "${BOLD}${CYAN}            Notion P298 (ASR1802S) Firmware Flasher             ${NC}\n"
        printf "${CYAN}================================================================${NC}\n\n"
        printf "No firmware target specified. Please select an option:\n\n"
        printf "  ${BOLD}1)${NC} ${GREEN}OpenWrt${NC}   (Linux 6.18 Kernel + SquashFS RootFS on Slot B)\n"
        printf "  ${BOLD}2)${NC} ${YELLOW}Stock${NC}     (Restore Factory Stock Firmware on Slot B)\n"
        printf "  ${BOLD}3)${NC} Exit\n\n"
        printf "Select choice [1-3]: "
        read -r choice
        case "$choice" in
            1) TARGET="openwrt" ;;
            2) TARGET="stock" ;;
            *) printf "\nCancelled.\n"; exit 0 ;;
        esac
    else
        printf "${RED}Error: No firmware target specified (use 'openwrt' or 'stock').${NC}\n" >&2
        usage
    fi
fi

# Set target configurations
case "$TARGET" in
    openwrt)
        TITLE="Notion P298 (ASR1802S) OpenWrt Slot B Flasher"
        FIRMWARE_DIR="$SCRIPT_DIR/firmware-openwrt"
        BLF_FILE="$FIRMWARE_DIR/p298-openwrt-slotb.blf"
        KERNEL_DESC="OpenWrt kernel (Linux 6.18)"
        ROOTFS_DESC="OpenWrt SquashFS rootfs"
        ;;
    stock)
        TITLE="Notion P298 (ASR1802S) Universal Stock Flasher"
        FIRMWARE_DIR="$SCRIPT_DIR/firmware"
        BLF_FILE="$FIRMWARE_DIR/p298-stock-slotb.blf"
        KERNEL_DESC="Stock Linux kernel"
        ROOTFS_DESC="Stock SquashFS rootfs"
        ;;
esac

# Pre-flight checks
if [ ! -x "$SWDL" ]; then
    printf "${RED}Error: Flasher utility not found or not executable: %s${NC}\n" "$SWDL" >&2
    exit 1
fi

if [ ! -f "$BLF_FILE" ]; then
    printf "${RED}Error: Flash descriptor not found: %s${NC}\n" "$BLF_FILE" >&2
    exit 1
fi

# Clean stale locks
rm -f "$TOOLS_DIR/swdlinux.pid" /tmp/swdlinux.pid 2>/dev/null || true

printf "\n${CYAN}================================================================${NC}\n"
printf "${BOLD}${CYAN}   %s   ${NC}\n" "$TITLE"
printf "${CYAN}================================================================${NC}\n\n"

printf "${BOLD}Target Profile:${NC} %s\n" "$TARGET"
printf "${BOLD}BLF Recipe:${NC}     %s\n\n" "$BLF_FILE"

printf "${BOLD}Hardware Instructions:${NC}\n"
printf "  1. Connect USB data cable between router and computer.\n"
printf "  2. Power on the router (or plug in 12V adapter) now.\n"
printf "  3. Flasher will automatically detect the board in download mode (2ecc:3002).\n\n"
printf "${CYAN}[*] Starting SWDownloader (waiting up to %ss for USB download mode)...${NC}\n\n" "$TIMEOUT"

# Execute SWDownloader in tools directory
set +e
( cd "$TOOLS_DIR" && env LC_ALL=C LANG=C ./swdl_linux -D "$BLF_FILE" -S -T "$TIMEOUT" )
RC=$?
set -e

printf "\n"
if [ $RC -eq 0 ]; then
    printf "${GREEN}================================================================${NC}\n"
    printf "${BOLD}${GREEN}                 FLASH COMPLETED SUCCESSFULLY!                  ${NC}\n"
    printf "${GREEN}================================================================${NC}\n"
    printf "  - %s written to Partition 14 (mtd14)\n" "$KERNEL_DESC"
    printf "  - %s written to Partition 16 (mtd16)\n" "$ROOTFS_DESC"
    printf "  - Universal DTIM-B written to Partition 8 (mtd8)\n"
    printf "  - Active boot slot set to Slot B (mtd19, quiet=0)\n"
    printf "  - RSA signature verification bypassed (mtd20)\n"
    printf "  - Clean bootargs/U-Boot env written to Partition 21 (mtd21)\n\n"
    printf "${BOLD}Flashing complete. Power cycle the router normally to boot.${NC}\n\n"
else
    printf "${RED}================================================================${NC}\n"
    printf "${BOLD}${RED}                      FLASHING FAILED                           ${NC}\n"
    printf "${RED}================================================================${NC}\n"
    printf "SWDownloader exited with error code: %s\n" "$RC"
    printf "Check USB cable connection, verify download mode (2ecc:3002), and retry.\n\n"
fi

exit "$RC"
