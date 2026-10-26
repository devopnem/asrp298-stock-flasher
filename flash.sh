#!/bin/sh
#
# Universal Stock Flasher for Notion P298 (ASR1802S / PXA1826)
#
# Flashes verified stock kernel (mtd14) and rootfs (mtd16) to Slot B
# using the universal hash-agnostic DTIM-B, active_slot='b', quiet=0,
# and NASR RSA signature bypass.
#
# Safe: preserves Slot A and all factory calibration/NVRAM partitions (mtd1..mtd6).
# Universal: boots on any board revision or factory firmware generation (2024, 2025, 2026).
#

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS_DIR="$SCRIPT_DIR/tools"
FIRMWARE_DIR="$SCRIPT_DIR/firmware"
BLF_FILE="$FIRMWARE_DIR/p298-stock-slotb.blf"
SWDL="$TOOLS_DIR/swdl_linux"
UART_DEV="/dev/ttyUSB0"
ENABLE_UART=1
TIMEOUT=600

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Usage / arguments
usage() {
    printf "${BOLD}Usage:${NC} %s [options]\n\n" "$0"
    printf "Options:\n"
    printf "  --uart <dev>       Serial console device (default: /dev/ttyUSB0)\n"
    printf "  --no-uart          Disable UART serial capture\n"
    printf "  -t, --timeout <s > USB download wait timeout in seconds (default: 600)\n"
    printf "  -h, --help         Show this help message\n\n"
    exit 0
}

# Parse help early before privilege escalation
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            ;;
    esac
done

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    if command -v doas >/dev/null 2>&1; then
        printf "${YELLOW}Privilege escalation required. Re-running with doas...${NC}\n"
        exec doas sh "$0" "$@"
    elif command -v sudo >/dev/null 2>&1; then
        printf "${YELLOW}Privilege escalation required. Re-running with sudo...${NC}\n"
        exec sudo sh "$0" "$@"
    else
        printf "${RED}Error: This script must be run as root (or install sudo/doas).${NC}\n" >&2
        exit 1
    fi
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --uart)
            UART_DEV="$2"
            shift 2
            ;;
        --no-uart)
            ENABLE_UART=0
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            printf "${RED}Unknown option: %s${NC}\n" "$1"
            usage
            ;;
    esac
done

printf "${CYAN}================================================================${NC}\n"
printf "${BOLD}${CYAN}   Notion P298 (ASR1802S) Universal Stock Unbrick & Flasher    ${NC}\n"
printf "${CYAN}================================================================${NC}\n\n"

# Pre-flight checks
if [ ! -x "$SWDL" ]; then
    printf "${RED}Error: Flasher binary not found or not executable: %s${NC}\n" "$SWDL" >&2
    exit 1
fi

if [ ! -f "$BLF_FILE" ]; then
    printf "${RED}Error: BLF configuration not found: %s${NC}\n" "$BLF_FILE" >&2
    exit 1
fi

# Clean stale locks
rm -f "$TOOLS_DIR/swdlinux.pid" /tmp/swdlinux.pid 2>/dev/null || true

# Prepare UART capture if enabled
UPID=
ULOG="$SCRIPT_DIR/uart_boot.log"
cleanup() {
    if [ -n "$UPID" ]; then
        kill "$UPID" 2>/dev/null || true
        wait "$UPID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if [ "$ENABLE_UART" -eq 1 ] && [ -e "$UART_DEV" ]; then
    printf "${BLUE}[*] UART console detected on %s. Capturing boot logs to %s...${NC}\n" "$UART_DEV" "$ULOG"
    # Configure 115200 8N1 raw if stty is present
    stty -F "$UART_DEV" 115200 raw -echo cs8 2>/dev/null || true
    cat "$UART_DEV" > "$ULOG" 2>&1 &
    UPID=$!
elif [ "$ENABLE_UART" -eq 1 ]; then
    printf "${YELLOW}[!] UART device %s not detected (skipping serial capture).${NC}\n" "$UART_DEV"
fi

printf "${BOLD}Hardware Instructions:${NC}\n"
printf "  1. Connect USB cable between router and computer.\n"
printf "  2. Short the ${YELLOW}USB_BOOT / download pin${NC} to ${YELLOW}GND${NC} (test point on PCB).\n"
printf "  3. Power on the router (or plug in 12V adapter).\n"
printf "  4. Once device ${GREEN}2ecc:3002${NC} is detected, release the short.\n\n"
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
    printf "  - Stock kernel written to Partition 14 (mtd14)\n"
    printf "  - Stock rootfs written to Partition 16 (mtd16)\n"
    printf "  - Universal DTIM-B written to Partition 8 (mtd8)\n"
    printf "  - Active boot slot switched to Slot B (mtd19, quiet=0)\n"
    printf "  - RSA signature verification bypassed (mtd20)\n"
    printf "  - Clean stock bootargs/U-Boot env written to Partition 21 (mtd21)\n\n"
    if [ -n "$UPID" ]; then
        printf "${BLUE}[*] Waiting 15 seconds to capture initial bootloader & kernel UART output...${NC}\n"
        sleep 15
        printf "${BLUE}[*] Boot log captured in: %s${NC}\n" "$ULOG"
    fi
    printf "${BOLD}The router will now boot into stock firmware on Slot B.${NC}\n"
    printf "Reboot the router normally (disconnect USB_BOOT pin, power-cycle).\n"
else
    printf "${RED}================================================================${NC}\n"
    printf "${BOLD}${RED}                      FLASHING FAILED                           ${NC}\n"
    printf "${RED}================================================================${NC}\n"
    printf "SWDownloader exited with error code: %s\n" "$RC"
    printf "Check USB connection, verify download mode pin (2ecc:3002), and try again.\n"
fi

exit "$RC"
