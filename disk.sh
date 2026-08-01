#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

OVERLAY=disk/overlay.qcow2
SWAP=disk/swap.qcow2

for tool in qemu-img truncate; do
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
  echo "macOS: brew install e2fsprogs" >&2
  exit 1
}

mkdir -p disk

for image in "$OVERLAY" "$SWAP"; do
  if [ -e "$image" ]; then
    echo "removing $image"
    rm -f "$image"
  fi
done

overlay_raw=$(mktemp "${TMPDIR:-/tmp}/alpine-overlay.XXXXXX")
overlay_tmp=$OVERLAY.tmp.$$
trap 'rm -f "$overlay_raw" "$overlay_tmp"' EXIT HUP INT TERM

echo "creating $OVERLAY (${OVERLAY_SIZE:-8G})"
truncate -s "${OVERLAY_SIZE:-8G}" "$overlay_raw"
"$mkfs_ext4" -q -F \
  -O ^has_journal,^resize_inode,^dir_index,sparse_super2,^metadata_csum_seed,^orphan_file,^64bit \
  -m 0 \
  -E lazy_itable_init=1,nodiscard \
  "$overlay_raw"

qemu-img convert \
  -f raw \
  -O qcow2 \
  -o cluster_size=64k,lazy_refcounts=on \
  "$overlay_raw" "$overlay_tmp"

mv "$overlay_tmp" "$OVERLAY"
rm -f "$overlay_raw"
trap - EXIT HUP INT TERM

swap_tmp=$SWAP.tmp.$$
trap 'rm -f "$swap_tmp"' EXIT HUP INT TERM

echo "creating $SWAP (${SWAP_SIZE:-2G})"
qemu-img create -q -f qcow2 "$swap_tmp" "${SWAP_SIZE:-2G}"
mv "$swap_tmp" "$SWAP"

trap - EXIT HUP INT TERM

qemu-img info "$OVERLAY"
qemu-img info "$SWAP"
