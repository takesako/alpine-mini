@echo off
cd /d "%~dp0"

if not exist "vfat\" mkdir "vfat"

set "KERNEL=img\vmlinuz-virt"
set "INITRAMFS=img\initramfs.cpio.gz"
set "ROOTFS=img\root.squashfs"
set "OVERLAY=img\overlay.qcow2"
set "SWAP=img\swap.qcow2"

qemu-system-x86_64.exe ^
  -m 128 ^
  -machine q35 ^
  -kernel "%KERNEL%" ^
  -initrd "%INITRAMFS%" ^
  -append "console=ttyS0 quiet" ^
  -nographic ^
  -no-reboot ^
  -drive file="%ROOTFS%",if=virtio,format=raw,readonly=on ^
  -drive file="%OVERLAY%",if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap ^
  -drive file="%SWAP%",if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap ^
  -drive file=fat:rw:vfat,format=raw,if=virtio,cache=directsync ^
  -netdev user,id=n0 ^
  -device virtio-net-pci,netdev=n0 ^
  -object rng-builtin,id=rng0 ^
  -device virtio-rng-pci,rng=rng0 ^
  -device qemu-xhci,id=xhci ^
  -device usb-host,vendorid=0x04b4,productid=0x8613 ^
  -device usb-host,vendorid=0x16d0,productid=0x0753 ^
 2>qemu-log.txt
