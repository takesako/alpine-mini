#!/bin/sh
set -eu

for file in vmlinuz-virt initramfs.cpio.gz root.squashfs; do
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

mkdir -p share

if [ ! -f overlay.qcow2 ]; then
  overlay_raw=$(mktemp "${TMPDIR:-/tmp}/alpine-overlay.XXXXXX")
  trap 'rm -f "$overlay_raw"' EXIT HUP INT TERM
  truncate -s "${OVERLAY_SIZE:-4G}" "$overlay_raw"
  "$mkfs_ext4" -q -F \
    -O ^has_journal,^metadata_csum_seed,^orphan_file,^64bit \
    -m 0 \
    -E lazy_itable_init=1 \
    "$overlay_raw"
  qemu-img convert -f raw -O qcow2 -c "$overlay_raw" overlay.qcow2
  rm -f "$overlay_raw"
  trap - EXIT HUP INT TERM
fi

[ -f swap.qcow2 ] ||
  qemu-img create -q -f qcow2 swap.qcow2 "${SWAP_SIZE:-1G}"

ssh_port=${SSH_PORT-}
if [ -n "$ssh_port" ]; then
  netdev="user,id=n0,hostfwd=tcp::$ssh_port-:22"
else
  netdev=user,id=n0
fi

set -- \
  qemu-system-x86_64 \
  -m "${MEMORY:-256M}" \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" \
  -nographic \
  -no-reboot \
  -drive file=root.squashfs,if=virtio,format=raw,readonly=on \
  -drive file=overlay.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -drive file=swap.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap \
  -netdev "$netdev" \
  -device virtio-net-pci,netdev=n0 \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-pci,rng=rng0 \
  -fsdev local,id=share,path=share,security_model=none \
  -device virtio-9p-pci,fsdev=share,mount_tag=share

if [ "${USB_PASSTHROUGH:-0}" = 1 ]; then
  set -- "$@" \
    -device qemu-xhci,id=xhci \
    -device usb-host,bus=xhci.0,vendorid=0x16d0,productid=0x0753 \
    -device usb-host,bus=xhci.0,vendorid=0x04b4,productid=0x8613 \
    -device usb-host,bus=xhci.0,vendorid=0xf055,productid=0x0002
fi

exec "$@"
