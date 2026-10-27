# Notion P298 (ASR1802S) Universal Stock Unbrick & Flashing Tool

A self-contained, turnkey unbricking and stock firmware flashing package for **Notion P298** (and OEM variants such as **Ooredoo R291 V2**) powered by the **ASR1802S / PXA1826** platform (board codename `KAGU`).

This tool restores bricked, soft-bricked, or bootlooping routers back to a clean, working stock Linux system on **Slot B**, completely preserving your router's unique calibration, IMEI, and MAC address partitions.

---

## ✨ Features & Universal Architecture

Unlike standard vendor packages which fail when flashing across different manufacturing dates or firmware versions, this package implements the **universal hash-agnostic DTIM flashing method**:

1. **Universal Zero-Hash Bypass (`size2 = 0`):**
   Under the Marvell TIM 3.4.0 specification, both the Primary Bootloader (OBM at `0x31fa4`) and U-Boot (`0x30d484`) check `ImageSizeToHash` (`size2` at offset `+0x14`). If `size2 == 0`, verification immediately returns `0` (PASS) without executing SHA-256 validation. By zeroing `size2` across all partition entries in DTIM-B (`mtd8`), the boot chain boots seamlessly **regardless of internal factory hash mismatches**.
2. **Multi-Generation U-Boot Compatibility (2024, 2025, 2026):**
   The `OSLO` descriptor in DTIM-B is configured with `size = 0x00080000` and `size2 = 0`. This guarantees OBM reads the complete U-Boot binary into RAM without truncating the 2026 U-Boot (`0x0007556c` bytes vs 2024's `0x000751b8` bytes), preventing rollback failures (`IMAP Image Valiate Error`).
3. **Hardware RSA Check Bypass (`mtd20` NASR):**
   Includes a modified `mtd20` image with byte `0x0C` patched `0x09 -> 0x00`, turning off RSA signature enforcement in OBM.
4. **Verbose Serial Console (`mtd19` `asr_flag`):**
   Patches `mtd19` with `quiet = 0` (`0x98 = 1`) and `active_slot = 'b'`, giving full visibility over the UART serial console during boot.
5. **Clean U-Boot Environment (`mtd21` Bootargs):**
   Flashes the clean factory stock U-Boot environment with valid CRC32, ensuring `bootcmd=mrvlboot`, `autostart=yes`, `bootdelay=1`, and `verify=no` are active—unbricking devices with corrupted or erased environment blocks.
6. **Completely Safe — Zero Risk to Calibration & NVM:**
   Flashing strictly targets **Slot B** (`mtd14` Kernel, `mtd16` RootFS, `mtd8` DTIM-B, `mtd19`, `mtd20`, and `mtd21` env). It **never** touches Slot A or the critical factory calibration / NVRAM / IMEI partitions (`mtd1` through `mtd6`).

---

## 📦 Package Contents

```
asrp298-stock-flasher/
├── flash.sh                 # Master unified flashing script (OpenWrt or Stock)
├── flash_openwrt.sh         # Shortcut for './flash.sh openwrt'
├── flash_stock.sh           # Shortcut for './flash.sh stock'
├── tools/
│   ├── swdl_linux           # ASR SWDownloader Linux x86_64 standalone binary
│   ├── fbfmake              # FBF image generator
│   ├── MakeDownloadPackage  # Download package utility
│   └── fbfdownloader        # Downloader protocol helper
├── firmware/                # Stock firmware images (Kernel mtd14, RootFS mtd16, BLF)
├── firmware-openwrt/        # OpenWrt firmware images (Kernel mtd14, RootFS mtd16, BLF)
└── udev/
    └── 99-asr1802s.rules    # Optional udev rule for USB download mode (2ecc:3002)
```

---

## 🛠️ Hardware Requirements

1. **USB Data Connection:**
   Connect a USB cable between the router and your Linux PC.
2. **Download Mode Entry (Automatic):**
   Connect the USB cable between the router and computer, start the flashing script, and then power on the router. The flasher detects the board and automatically enters download mode (`2ecc:3002`). (Test point shorting of `USB_BOOT` to `GND` is only needed as an emergency fallback if the board fails to handshake).
3. **Optional: UART Serial Cable (1.8V TTL):**
   - Baud rate: `115200 8N1`
   - Pins: `GND`, `TX`, `RX` (Do **not** connect 3.3V/5V VCC!)
   - Serial port: typically `/dev/ttyUSB0`

---

## 🚀 Step-by-Step Flashing Guide

### 1. Install udev Rules (Optional, recommended)

```bash
sudo cp udev/99-asr1802s.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 2. Run the Flasher

Launch the automated script to flash OpenWrt or restore Stock firmware:

```bash
# Flash OpenWrt (kernel + rootfs) to Slot B:
./flash.sh openwrt
# or shortcut:
./flash_openwrt.sh

# Restore factory stock Linux firmware to Slot B:
./flash.sh stock
# or shortcut:
./flash_stock.sh
```

### 3. Enter Download Mode

When the script displays:

```
[*] Starting SWDownloader (waiting up to 600s for USB download mode)...
Please plug your USB device
```

1. Ensure the USB cable is connected between the router and computer.
2. Start the flashing script (`./flash.sh` or `./flash_openwrt.sh`).
3. Turn on the router (or plug in the 12V power supply). The flasher detects the board and transitions it automatically into download mode (`2ecc:3002`).

### 4. Flashing Progress & Completion

SWDownloader will automatically upload the FBF package and flash the partitions:

```
|Start Image Downloading...:  /dev/bus/usb/001/048   |
|Completed DownLoad file: /tmp/SWD-XXXXXX/temp/FBF_h.bin   |
|Begin Burning flash...:  /dev/bus/usb/001/048   |
|/dev/bus/usb/001/048:Burn Successfully                |
```

The router will now boot into clean stock firmware on **Slot B**!

---

## 🔑 Stock Credentials & SSH Access

Once flashed and booted into the stock firmware, you can connect to the router via LAN/Ethernet or Wi-Fi:

- **Default Router IP:** `192.168.1.1`
- **SSH Service:** Dropbear (enabled by `dropbear_mode=1` in the `mtd21` environment)
- **SSH Username:** `root`
- **SSH Password:** `85719364` *(configured in `mtd21` as `dropbear_password=85719364`)*

To log in:
```bash
ssh root@192.168.1.1
# When prompted, enter password: 85719364
```

> [!TIP]
> If your modern OpenSSH client rejects older legacy ciphers/key-exchange algorithms used by the stock Dropbear daemon, connect using:
> ```bash
> ssh -oHostKeyAlgorithms=+ssh-rsa -oKexAlgorithms=+diffie-hellman-group1-sha1 -oCiphers=+aes128-cbc root@192.168.1.1
> ```

---

## 🗺️ Partition Map Reference

| Partition | Offset       | Size        | Name     | Description / Role in this Flasher       |
|-----------|--------------|-------------|----------|------------------------------------------|
| `mtd0`    | `0x00000000` | 256 KB      | `OBM`    | Primary bootloader in ROM (read-only)    |
| `mtd1`..`6` | `0x00040000`..| -        | NVRAM/CAL| Factory calibration & IMEI (**Untouched**)|
| `mtd7`    | `0x00100000` | 256 KB      | `DTIM-A` | Slot A Device TIM (**Untouched**)        |
| `mtd8`    | `0x00140000` | 256 KB      | `DTIM-B` | **Flashed**: Universal No-Verify DTIM-B  |
| `mtd11`   | `0x01FC0000` | 512 KB      | `U-BOOT-A`| Slot A U-Boot (**Untouched**)           |
| `mtd12`   | `0x02040000` | 512 KB      | `U-BOOT-B`| Slot B U-Boot (Loaded by universal DTIM) |
| `mtd13`   | `0x02100000` | 5 MB        | `KERNEL-A`| Slot A Kernel (**Untouched**)           |
| `mtd14`   | `0x02600000` | 5 MB        | `KERNEL-B`| **Flashed**: Stock Linux Kernel (mtd14)  |
| `mtd15`   | `0x02B00000` | 20 MB       | `ROOTFS-A`| Slot A RootFS (**Untouched**)           |
| `mtd16`   | `0x03F00000` | 20 MB       | `ROOTFS-B`| **Flashed**: Stock SquashFS RootFS (mtd16)|
| `mtd19`   | `0x05F00000` | 768 KB      | `asr_flag`| **Flashed**: Active slot `'b'`, quiet=0  |
| `mtd20`   | `0x05FC0000` | 256 KB      | `nasr`   | **Flashed**: RSA signature bypass        |
| `mtd21`   | `0x06000000` | 256 KB      | `env`    | **Flashed**: Clean stock U-Boot env / bootargs |

---

## ❓ Troubleshooting

- **`swdl_linux` hangs on "Please plug your USB device":**
  Ensure the `USB_BOOT` pin is firmly grounded before applying power. Run `lsusb` to verify that `2ecc:3002` appears.
- **Permission Denied / Port Busy:**
  Make sure `swdlinux.pid` is removed (`rm -f /tmp/swdlinux.pid tools/swdlinux.pid`) and that you run the script with root privileges (`sudo` or `doas`).
- **UART output shows garbage:**
  The serial console on the ASR1802S operates at **1.8V logic level** at **115200 baud, 8 data bits, no parity, 1 stop bit (115200 8N1)**. Ensure your USB-UART adapter supports 1.8V I/O.

---

## 📄 License

This repository is licensed under the [MIT License](LICENSE).
Firmware images are stock binaries extracted from the manufacturer's publicly distributed devices for repair and interoperability purposes.
