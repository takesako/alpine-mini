#!/bin/sh
set -eu

R=https://dl-cdn.alpinelinux.org/alpine/v3.24
A=x86_64 P=packages F=rootfs T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$P"

get(){
  N=$(curl -fsSL "$R/main/$A/" | sed -n "s/.*href=\"\($1-[0-9][^\"]*\.apk\)\".*/\1/p" | sort -V | tail -1)
  [ -f "$P/$1.apk" ] || curl -fL "$R/main/$A/$N" -o "$P/$1.apk"
  mkdir -p "$T/$1"; tar -xf "$P/$1.apk" -C "$T/$1"
}

for n in busybox-static apk-tools-static alpine-keys ca-certificates-bundle linux-virt
do get "$n"; done

rm -rf "$F"
for d in bin sbin usr/bin usr/sbin usr/share/udhcpc etc/apk/keys etc/ssl/certs \
  lib/apk/db var/lib/apk proc sys dev tmp run root newroot mnt/share
do mkdir -p "$F/$d"; done

cp "$T/busybox-static/bin/busybox.static" "$F/bin/busybox"
cp "$T/apk-tools-static/sbin/apk.static" "$F/sbin/apk"
chmod 755 "$F/bin/busybox" "$F/sbin/apk"

for x in sh test true false printf cat head tail echo touch cp mv rm mkdir rmdir \
  ln ls stat find grep sed awk cut sort uniq wc xargs chmod chown date uptime \
  uname hostname sleep tar cpio gzip gunzip dd sync ps free df du kill dmesg \
  vi ip ping nslookup wget udhcpc mount umount switch_root chroot setsid blkid \
  mkswap swapon swapoff lsmod insmod rmmod reboot poweroff
do ln -sf /bin/busybox "$F/bin/$x"; done

for x in mount umount switch_root chroot udhcpc blkid mkswap swapon swapoff \
  lsmod insmod rmmod reboot poweroff
do ln -sf /bin/busybox "$F/sbin/$x"; done

cp "$T/alpine-keys/etc/apk/keys/"* "$F/etc/apk/keys/"
cp "$T/ca-certificates-bundle/etc/ssl/certs/ca-certificates.crt" "$F/etc/ssl/certs/"

L=$T/linux-virt
K=$(basename "$(find "$L/lib/modules" -mindepth 1 -maxdepth 1 -type d)")
M=$L/lib/modules/$K E=$F/etc/modules D=$T/done
cp "$L/boot/vmlinuz-virt" vmlinuz-virt
: >"$E"; : >"$D"

mod()
(
  X=$1
  grep -qxF "$X" "$D" && exit
  echo "$X" >>"$D"
  for Y in $(sed -n "s|^$X: ||p" "$M/modules.dep"); do mod "$Y"; done
  S=$M/$X Q=/lib/modules/$K/${X%.gz}; Q=${Q%.zst}
  mkdir -p "$F/${Q%/*}"
  case "$S" in
    *.gz) gzip -dc "$S" >"$F$Q";;
    *.zst) zstd -q -dc "$S" >"$F$Q";;
    *) cp "$S" "$F$Q";;
  esac
  echo "$Q" >>"$E"
)

for n in virtio_net virtio-rng af_packet virtio_blk ext4 \
  9p 9pnet 9pnet_virtio \
  xhci-hcd xhci-pci usbcore usb-common \
  hid usbhid hid-generic
do
  X=$(find "$M" -type f \( -name "$n.ko" -o -name "$n.ko.gz" -o -name "$n.ko.zst" \) | head -1)
  [ -n "$X" ] || { echo "module not found: $n"; exit 1; }
  mod "${X#"$M/"}"
done

awk '!a[$0]++' "$E" >"$E.tmp"; mv "$E.tmp" "$E"

cat >"$F/etc/apk/repositories" <<EOF
$R/main
$R/community
EOF

cat >"$F/usr/share/udhcpc/default.script" <<'EOF'
#!/bin/sh
case "$1" in
  deconfig) ip addr flush dev "$interface";;
  bound|renew)
    ip addr flush dev "$interface"
    ip addr add "$ip/24" dev "$interface"
    ip route del default 2>/dev/null || true
    ip route add default via "${router%% *}" dev "$interface"
    : >/etc/resolv.conf
    for x in $dns; do echo "nameserver $x" >>/etc/resolv.conf; done
esac
EOF

echo 'root:x:0:0:root:/root:/bin/sh' >"$F/etc/passwd"
echo 'root:x:0:' >"$F/etc/group"
echo alpine >"$F/etc/hostname"
echo 'nameserver 10.0.2.3' >"$F/etc/resolv.conf"
: >"$F/lib/apk/db/installed"

cat >"$F/init" <<'EOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
while read -r m; do insmod "$m" || exec sh </dev/console >/dev/console 2>&1; done </etc/modules
mount -t ext4 -o noatime,nodiratime /dev/vda /newroot ||
  exec sh </dev/console >/dev/console 2>&1
[ -e /newroot/sbin/init ] || cp -a /bin /sbin /usr /etc /lib /root /var /newroot/
for d in proc sys dev tmp run mnt/share; do mkdir -p "/newroot/$d"; done
mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
mount --move /dev /newroot/dev
exec switch_root /newroot /sbin/init
EOF

cat >"$F/sbin/init" <<'EOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
hostname alpine
ip link set lo up
ip link set eth0 up
udhcpc -i eth0 -s /usr/share/udhcpc/default.script
mkdir -p /mnt/share
mount -t 9p -o trans=virtio,version=9p2000.L,cache=loose share /mnt/share ||
  echo "share mount failed"
if [ -b /dev/vdb ]; then
  swapon /dev/vdb 2>/dev/null || {
    mkswap /dev/vdb
    swapon /dev/vdb
  }
fi
exec setsid sh -c 'exec sh </dev/ttyS0 >/dev/ttyS0 2>&1'
EOF

chmod 755 "$F/init" "$F/sbin/init" "$F/usr/share/udhcpc/default.script"
(cd "$F"; find . | cpio -o -H newc 2>/dev/null | gzip -9) >initramfs.cpio.gz
ls -lh vmlinuz-virt initramfs.cpio.gz
