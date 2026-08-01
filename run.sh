#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

mkdir -p vfat

KERNEL=img/vmlinuz-virt
INITRAMFS=img/initramfs.cpio.gz
ROOTFS=img/root.squashfs
OVERLAY=disk/overlay.qcow2
SWAP=disk/swap.qcow2
export TZ=UTC0

exec qemu-system-x86_64 \
  -m 128 \
  -machine q35 \
  -kernel "$KERNEL" \
  -initrd "$INITRAMFS" \
  -rtc base=utc,clock=host \
  -append "console=hvc0 quiet" \
  -display none \
  -serial none \
  -chardev stdio,id=console0,signal=off \
  -device virtio-serial-pci \
  -device virtconsole,chardev=console0 \
  -chardev socket,id=monitor0,host=127.0.0.1,port=4444,server=on,wait=off,nodelay=on \
  -mon chardev=monitor0,mode=readline \
  -no-reboot \
  -drive file="$ROOTFS",if=virtio,format=raw,readonly=on \
  -drive file="$OVERLAY",if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -drive file="$SWAP",if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -drive file=fat:rw:vfat,format=raw,if=virtio,cache=directsync \
  -netdev user,id=n0 \
  -device virtio-net-pci,netdev=n0 \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:7777-:7777,hostfwd=tcp:127.0.0.1:8888-:8888 \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-pci,rng=rng0 \
  -device qemu-xhci,id=xhci \
  -device usb-host,vendorid=0x04b4,productid=0x8613 \
  -device usb-host,vendorid=0x16d0,productid=0x0753 \
  2>qemu-log
