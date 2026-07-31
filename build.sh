#!/bin/sh
set -eu

REPOSITORY=https://dl-cdn.alpinelinux.org/alpine/v3.24
ARCH=x86_64
IMAGES=img
PACKAGES=tmp/packages
INITRAMFS=tmp/initramfs-root
ROOTFS=tmp/rootfs
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for tool in curl cpio gzip mksquashfs zstd; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "required command not found: $tool" >&2
    exit 1
  }
done

mkdir -p "$IMAGES" "$PACKAGES"

get()
{
  name=$1
  filename=$(
    curl -fsSL "$REPOSITORY/main/$ARCH/" |
      sed -n "s/.*href=\"\\($name-[0-9][^\"]*\\.apk\\)\".*/\\1/p" |
      sort -V |
      tail -1
  )
  [ -n "$filename" ] || {
    echo "package not found: $name" >&2
    exit 1
  }
  archive=$PACKAGES/$filename
  [ -f "$archive" ] ||
    curl -fL "$REPOSITORY/main/$ARCH/$filename" -o "$archive"
  mkdir -p "$TMP/$name"
  tar -xf "$archive" -C "$TMP/$name"
}

for name in busybox-static linux-virt; do
  get "$name"
done

for repository in main community; do
  curl -fsSL "$REPOSITORY/$repository/$ARCH/APKINDEX.tar.gz" |
    tar -xzOf - APKINDEX >"$TMP/APKINDEX.$repository"
done

install_order=$TMP/install-order
roots='alpine-base alpine-keys ssl_client ca-certificates doas'

awk -v roots="$roots" '
  BEGIN { RS = ""; FS = "\n" }
  {
    package = version = dependencies = provides = ""
    repository = FILENAME ~ /community$/ ? "community" : "main"
    for (line = 1; line <= NF; line++) {
      if ($line ~ /^P:/) package = substr($line, 3)
      if ($line ~ /^V:/) version = substr($line, 3)
      if ($line ~ /^D:/) dependencies = substr($line, 3)
      if ($line ~ /^p:/) provides = provides " " substr($line, 3)
    }
    package_repository[package] = repository
    package_version[package] = version
    package_dependencies[package] = dependencies
    count = split(provides, provided, /[[:space:]]+/)
    for (item = 1; item <= count; item++) {
      sub(/=.*/, "", provided[item])
      if (provided[item] != "" && !(provided[item] in provider))
        provider[provided[item]] = package
    }
  }
  function resolve(dependency, package, count, children, item) {
    if (dependency ~ /^!/) return
    if (dependency == "/bin/sh") dependency = "cmd:sh"
    sub(/[<>=~].*/, "", dependency)
    if (dependency == "") return
    package = dependency
    if (!(package in package_version)) package = provider[dependency]
    if (package == "") {
      print "dependency not found: " dependency >"/dev/stderr"
      failed = 1
      return
    }
    if (seen[package]++) return
    print package_repository[package] "|" package "|" package_version[package]
    count = split(package_dependencies[package], children, /[[:space:]]+/)
    for (item = 1; item <= count; item++) resolve(children[item])
  }
  END {
    count = split(roots, root, /[[:space:]]+/)
    for (item = 1; item <= count; item++) resolve(root[item])
    if (failed) exit 1
  }
' "$TMP/APKINDEX.main" "$TMP/APKINDEX.community" >"$install_order"

rm -rf "$INITRAMFS" "$ROOTFS"

# The initramfs contains only BusyBox, boot-critical kernel modules, /init,
# and the empty directories needed before switch_root.
for dir in bin dev newroot overlay proc run sys; do
  mkdir -p "$INITRAMFS/$dir"
done
cp "$TMP/busybox-static/bin/busybox.static" "$INITRAMFS/bin/busybox"
chmod 755 "$INITRAMFS/bin/busybox"

# The complete mutable-looking Alpine userland lives in the read-only
# SquashFS lower layer. Runtime changes are redirected to overlay.qcow2.
for dir in \
  bin sbin usr/bin usr/sbin usr/share/udhcpc etc/apk/keys etc/ssl/certs \
  lib/apk/db var/cache/apk var/lib/apk proc sys dev tmp run root vfat
do
  mkdir -p "$ROOTFS/$dir"
done

while IFS='|' read -r repository package version; do
  filename=$package-$version.apk
  archive=$PACKAGES/$filename
  [ -f "$archive" ] ||
    curl -fL "$REPOSITORY/$repository/$ARCH/$filename" -o "$archive"
  tar -tf "$archive" | awk '$0 !~ /^\./' >"$TMP/files"
  tar -xf "$archive" -C "$ROOTFS" -T "$TMP/files"
done <"$install_order"

release_package_version=$(
  awk -F '|' '$2 == "alpine-release" { print $3; exit }' "$install_order"
)
release_version=${release_package_version%-r*}
minirootfs=alpine-minirootfs-$release_version-$ARCH.tar.gz
minirootfs_archive=$PACKAGES/$minirootfs
[ -f "$minirootfs_archive" ] ||
  curl -fL \
    "$REPOSITORY/releases/$ARCH/$minirootfs" \
    -o "$minirootfs_archive"

rm -rf "$ROOTFS/lib/apk/db"
tar -xzf "$minirootfs_archive" -C "$ROOTFS" ./lib/apk/db

while IFS='|' read -r repository package version; do
  grep -qxF "P:$package" "$ROOTFS/lib/apk/db/installed" && continue
  awk -v package="$package" '
    BEGIN { RS = ""; FS = "\n" }
    {
      for (line = 1; line <= NF; line++) {
        if ($line == "P:" package) {
          print $0 "\n"
          exit
        }
      }
    }
  ' "$TMP/APKINDEX.$repository" >>"$ROOTFS/lib/apk/db/installed"
done <"$install_order"

find "$ROOTFS" -maxdepth 1 -type f -name '.*' -delete
[ ! -e "$ROOTFS/bin/bbsuid" ] || chmod 4755 "$ROOTFS/bin/bbsuid"
[ ! -e "$ROOTFS/usr/bin/doas" ] || chmod 4755 "$ROOTFS/usr/bin/doas"
cut -d '|' -f 2- "$install_order" >"$ROOTFS/etc/alpine-mini-packages"
printf '%s\n' $roots >"$ROOTFS/etc/apk/world"
echo "$ARCH" >"$ROOTFS/etc/apk/arch"

while read -r applet; do
  [ -n "$applet" ] || continue
  [ -e "$ROOTFS/$applet" ] || [ -L "$ROOTFS/$applet" ] ||
    ln -s /bin/busybox "$ROOTFS/$applet"
done <"$ROOTFS/etc/busybox-paths.d/busybox"

# Create the regular user and allow wheel members to use doas without a password.
mkdir -p "$ROOTFS/etc/doas.d" "$ROOTFS/home/user"
echo 'permit nopass :wheel' >"$ROOTFS/etc/doas.d/wheel.conf"
chmod 600 "$ROOTFS/etc/doas.d/wheel.conf"
echo 'user:x:1000:100::/home/user:/bin/sh' >>"$ROOTFS/etc/passwd"
echo 'user:$6$WcQlkbULYKUjvmhj$YSOvzqOF9ZbpdQcKl24kWAwrEqIeFjNOgkM6LKj0O1G4iMGI9Dnx2tLoye1hOmjy82ORmRsXmEN0DuPvKOYYJ1:20665:0:99999:7:::' >>"$ROOTFS/etc/shadow"
awk -F: 'BEGIN { OFS=FS } $1 == "wheel" { $4 = $4 ? $4 ",user" : "user" } { print }' \
  "$ROOTFS/etc/group" >"$TMP/group"
cat "$TMP/group" >"$ROOTFS/etc/group"
ln -s /vfat "$ROOTFS/home/user/vfat"

linux=$TMP/linux-virt
kernel_version=$(basename "$(find "$linux/lib/modules" -mindepth 1 -maxdepth 1 -type d)")
modules=$linux/lib/modules/$kernel_version
module_list=$TMP/modules
module_done=$TMP/modules.done
cp "$linux/boot/vmlinuz-virt" "$IMAGES/vmlinuz-virt"
: >"$module_list"
: >"$module_done"

copy_module()
(
  module=$1
  grep -qxF "$module" "$module_done" && exit
  echo "$module" >>"$module_done"
  for dependency in $(sed -n "s|^$module: ||p" "$modules/modules.dep"); do
    copy_module "$dependency"
  done
  source=$modules/$module
  target=/lib/modules/$kernel_version/${module%.gz}
  target=${target%.zst}
  mkdir -p "$INITRAMFS/${target%/*}"
  case "$source" in
    *.gz) gzip -dc "$source" >"$INITRAMFS$target" ;;
    *.zst) zstd -q -dc "$source" >"$INITRAMFS$target" ;;
    *) cp "$source" "$INITRAMFS$target" ;;
  esac
  echo "$target" >>"$module_list"
)

for name in \
  virtio_net virtio-rng af_packet virtio_blk ext4 squashfs overlay \
  fat vfat nls_cp437 nls_utf8 \
  xhci-hcd xhci-pci ehci-hcd ehci-pci uhci-hcd usbcore usb-common hid usbhid hid-generic
do
  module=$(
    find "$modules" -type f \
      \( -name "$name.ko" -o -name "$name.ko.gz" -o -name "$name.ko.zst" \) |
      head -1
  )
  [ -n "$module" ] || {
    echo "module not found: $name" >&2
    exit 1
  }
  copy_module "${module#"$modules/"}"
done

awk '!seen[$0]++' "$module_list" >"$module_list.unique"

cat >"$INITRAMFS/init" <<'EOF'
#!/bin/busybox sh
BB=/bin/busybox
export PATH=/bin

fail()
{
  echo "initramfs: $*" >/dev/console
  exec $BB sh </dev/console >/dev/console 2>&1
}

$BB mount -t proc proc /proc || fail "cannot mount proc"
$BB mount -t sysfs sysfs /sys || fail "cannot mount sysfs"
$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
EOF

while read -r module; do
  printf '$BB insmod "%s" || fail "cannot load %s"\n' "$module" "$module" \
    >>"$INITRAMFS/init"
done <"$module_list.unique"

cat >>"$INITRAMFS/init" <<'EOF'

$BB mount -t ext4 -o noatime,nodiratime,discard /dev/vdb /overlay ||
  fail "cannot mount overlay.qcow2"
$BB mkdir -p /overlay/lower /overlay/upper /overlay/work
$BB mount -t squashfs -o ro /dev/vda /overlay/lower ||
  fail "cannot mount root.squashfs"
$BB mount -t overlay overlay \
  -o lowerdir=/overlay/lower,upperdir=/overlay/upper,workdir=/overlay/work \
  /newroot ||
  fail "cannot mount overlay root"

$BB mkdir -p /newroot/overlay
$BB mount --move /overlay /newroot/overlay ||
  fail "cannot expose overlay layers"

for directory in proc sys dev; do
  $BB mount --move "/$directory" "/newroot/$directory" ||
    fail "cannot move $directory"
done

exec $BB switch_root /newroot /sbin/boot
EOF

cat >"$ROOTFS/etc/apk/repositories" <<EOF
$REPOSITORY/main
$REPOSITORY/community
EOF

cat >"$ROOTFS/usr/share/udhcpc/default.script" <<'EOF'
#!/bin/sh
case "$1" in
  deconfig)
    ip addr flush dev "$interface"
    ;;
  bound|renew)
    ip addr flush dev "$interface"
    ip addr add "$ip/24" dev "$interface"
    ip route del default 2>/dev/null || true
    ip route add default via "${router%% *}" dev "$interface"
    : >/etc/resolv.conf
    for server in $dns; do
      echo "nameserver $server" >>/etc/resolv.conf
    done
    ;;
esac
EOF

echo alpine >"$ROOTFS/etc/hostname"
echo 'nameserver 10.0.2.3' >"$ROOTFS/etc/resolv.conf"
echo 'Welcome to Alpine!' >"$ROOTFS/etc/motd"

cat >"$ROOTFS/sbin/boot" <<'EOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

hostname alpine
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /tmp
ip link set lo up
ip link set eth0 up
udhcpc -i eth0 -s /usr/share/udhcpc/default.script

mkdir -p /vfat
mount -t vfat -o rw,sync,dirsync,uid=1000,gid=100 /dev/vdd1 /vfat ||
  echo "vfat mount failed"

# mksquashfs -all-root stores the lower layer as root-owned. Copy up the
# home directory metadata so user can write to it through OverlayFS.
chown 1000:100 /home/user
chmod 755 /home/user

if [ -b /dev/vdc ]; then
  swapon /dev/vdc 2>/dev/null || {
    mkswap /dev/vdc
    swapon /dev/vdc
  }
fi

syslogd

exec setsid sh -c 'exec /bin/login -f user </dev/ttyS0 >/dev/ttyS0 2>&1'
EOF

rm -f "$ROOTFS/sbin/poweroff" "$ROOTFS/sbin/halt"

cat >"$ROOTFS/sbin/poweroff" <<'EOF'
#!/bin/sh
[ "$(id -u)" -eq 0 ] || exec doas "$0" "$@"
sync
sync
umount /vfat
fstrim /overlay
exec /bin/busybox poweroff -f
EOF

cat >"$ROOTFS/sbin/halt" <<'EOF'
#!/bin/sh
[ "$(id -u)" -eq 0 ] || exec doas "$0" "$@"
rm -f /root/.ash_history
rm -f /home/user/.ash_history
rm -rf /var/log/*
sync
sync
umount /vfat
fstrim /overlay
exec /bin/busybox halt -f
EOF

chmod 755 \
  "$INITRAMFS/init" \
  "$ROOTFS/sbin/boot" \
  "$ROOTFS/sbin/poweroff" \
  "$ROOTFS/sbin/halt" \
  "$ROOTFS/usr/share/udhcpc/default.script"

mksquashfs "$ROOTFS" "$IMAGES/root.squashfs" \
  -noappend -all-root -no-xattrs -no-progress \
  -comp zstd -Xcompression-level 15 -quiet

(
  cd "$INITRAMFS"
  find . -print |
    cpio -o -H newc -R 0:0 2>/dev/null |
    gzip -9
) >"$IMAGES/initramfs.cpio.gz"

ls -lh \
  "$IMAGES/vmlinuz-virt" \
  "$IMAGES/initramfs.cpio.gz" \
  "$IMAGES/root.squashfs"
