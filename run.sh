#!/bin/sh
set -eu

IMAGES=img
KERNEL=$IMAGES/vmlinuz-virt
INITRAMFS=$IMAGES/initramfs.cpio.gz
ROOTFS=$IMAGES/root.squashfs
OVERLAY=$IMAGES/overlay.qcow2
SWAP=$IMAGES/swap.qcow2

for file in "$KERNEL" "$INITRAMFS" "$ROOTFS"; do
  [ -f "$file" ] || {
    echo "missing $file; run: sh build.sh" >&2
    exit 1
  }
done

for tool in qemu-img qemu-system-x86_64; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "required command not found: $tool" >&2
    exit 1
  }
done

mkfs_ext4=$(command -v mkfs.ext4 || true)
if [ -z "$mkfs_ext4" ] && command -v brew >/dev/null 2>&1; then
  candidate=$(brew --prefix e2fsprogs 2>/dev/null)/sbin/mkfs.ext4
  [ ! -x "$candidate" ] || mkfs_ext4=$candidate
fi
[ -n "$mkfs_ext4" ] || {
  echo "required command not found: mkfs.ext4" >&2
  exit 1
}

mkdir -p "$IMAGES" share

if [ ! -f "$OVERLAY" ]; then
  overlay_raw=$(mktemp "${TMPDIR:-/tmp}/alpine-overlay.XXXXXX")
  trap 'rm -f "$overlay_raw"' EXIT HUP INT TERM
  truncate -s "${OVERLAY_SIZE:-20G}" "$overlay_raw"
  "$mkfs_ext4" -q -F \
    -O ^has_journal,^resize_inode,^dir_index,^metadata_csum_seed,^orphan_file,^64bit \
    -m 0 \
    -E lazy_itable_init=1,nodiscard \
    "$overlay_raw"
  qemu-img convert -f raw -O qcow2 -o cluster_size=64k,lazy_refcounts=on "$overlay_raw" "$OVERLAY"
  rm -f "$overlay_raw"
  trap - EXIT HUP INT TERM
fi

[ -f "$SWAP" ] ||
  qemu-img create -q -f qcow2 "$SWAP" "${SWAP_SIZE:-2G}"

qemu-system-x86_64 \
  -m 256 \
  -kernel "$KERNEL" \
  -initrd "$INITRAMFS" \
  -append "console=ttyS0 quiet" \
  -nographic \
  -no-reboot \
  -drive file="$ROOTFS",if=virtio,format=raw,readonly=on \
  -drive file="$OVERLAY",if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -drive file="$SWAP",if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -drive file=fat:rw:share,format=raw,if=virtio \
  -netdev user,id=n0 \
  -device virtio-net-pci,netdev=n0 \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-pci,rng=rng0 \
  -fsdev local,id=share,path=.,security_model=none \
  -device virtio-9p-pci,fsdev=share,mount_tag=share \
  -device qemu-xhci,id=xhci \
  -device usb-host,bus=xhci.0,vendorid=0x16d0,productid=0x0753 \
  -device usb-host,bus=xhci.0,vendorid=0x04b4,productid=0x8613 \
  -device usb-host,bus=xhci.0,vendorid=0xf055,productid=0x0002
