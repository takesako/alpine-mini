#!/bin/sh
set -eu

mkdir -p share

if [ ! -f root.qcow2 ]; then
  truncate -s 4G root.raw
  mkfs.ext4 -q -F \
    -O ^has_journal,^metadata_csum_seed,^orphan_file,^64bit \
    -m 0 \
    -E lazy_itable_init=1 \
    root.raw
  qemu-img convert -f raw -O qcow2 -c root.raw root.qcow2
  rm root.raw
fi

[ -f swap.qcow2 ] || qemu-img create -q -f qcow2 swap.qcow2 1G

exec qemu-system-x86_64 \
  -m 256M \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" \
  -nographic \
  -no-reboot \
  -drive file=root.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -drive file=swap.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=n0 \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-pci,rng=rng0 \
  -fsdev local,id=share,path=share,security_model=none \
  -device virtio-9p-pci,fsdev=share,mount_tag=share \
  -device qemu-xhci,id=xhci \
  -device usb-host,bus=xhci.0,vendorid=0x16d0,productid=0x0753 \
  -device usb-host,bus=xhci.0,vendorid=0x04b4,productid=0x8613 \
  -device usb-host,bus=xhci.0,vendorid=0xf055,productid=0x0002
