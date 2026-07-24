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

for x in \
  '[' '[[' acpid add-shell addgroup adduser adjtimex arch arp arping ash awk \
  base64 basename bbconfig bc beep blkdiscard blkid blockdev brctl bunzip2 \
  bzcat bzip2 cal cat chattr chgrp chmod chown chpasswd chroot chvt cksum \
  clear cmp comm cp cpio crond crontab cryptpw cut date dc dd deallocvt \
  delgroup deluser depmod df diff dirname dmesg dnsdomainname dos2unix du \
  dumpkmap echo egrep eject env ether-wake expand expr factor fallocate \
  false fatattr fbset fbsplash fdflush fdisk fgrep find findfs flock fold \
  free fsck fstrim fsync fuser getopt getty grep groups gunzip gzip halt hd \
  head hexdump hostid hostname hwclock id ifconfig ifdown ifenslave ifup init \
  inotifyd insmod install ionice iostat ip ipaddr ipcalc ipcrm ipcs iplink \
  ipneigh iproute iprule iptunnel kbd_mode kill killall killall5 klogd last \
  less link linux32 linux64 ln loadfont loadkmap logger login logread losetup \
  ls lsattr lsmod lsof lsusb lzcat lzma lzop lzopcat makemime md5sum mdev \
  mesg microcom mkdir mkdosfs mkfifo mkfs.vfat mknod mkpasswd mkswap mktemp \
  modinfo modprobe more mount mountpoint mpstat mv nameif nanddump nandwrite \
  nbd-client nc netstat nice nl nmeter nohup nologin nproc nsenter nslookup \
  ntpd od openvt partprobe passwd paste pgrep pidof ping ping6 pipe_progress \
  pivot_root pkill pmap poweroff printenv printf ps pscan pstree pwd pwdx \
  raidautorun rdate rdev readahead readlink realpath reboot reformime \
  remove-shell renice reset resize rev rfkill rm rmdir rmmod route run-parts \
  sed sendmail seq setconsole setfont setkeycodes setlogcons setpriv setserial \
  setsid sh sha1sum sha256sum sha3sum sha512sum showkey shred shuf slattach \
  sleep sort split ssl_client stat strings stty su sum swapoff swapon \
  switch_root sync sysctl syslogd tac tail tar tee test time timeout top touch \
  tr traceroute traceroute6 tree true truncate tty ttysize tunctl udhcpc \
  udhcpc6 umount uname unexpand uniq unix2dos unlink unlzma unlzop unshare \
  unxz unzip uptime usleep uudecode uuencode vconfig vi vlock volname watch \
  watchdog wc wget which who whoami whois xargs xxd xzcat yes zcat zcip
do
  ln -sf /bin/busybox "$F/bin/$x"
done

for x in \
  acpid add-shell addgroup adduser adjtimex arp arping blkdiscard blkid \
  blockdev brctl chpasswd chroot crond cryptpw deallocvt delgroup deluser \
  depmod fdflush fdisk findfs fsck fstrim getty halt hwclock ifconfig ifdown \
  ifenslave ifup insmod ip klogd loadfont loadkmap logread losetup lsmod \
  mdev mkdosfs mkfs.vfat mknod mkpasswd mkswap modinfo modprobe mount \
  nameif nanddump nandwrite nbd-client partprobe pivot_root poweroff rdate \
  rdev readahead reboot remove-shell rfkill rmmod route setconsole setfont \
  setkeycodes setlogcons setserial slattach swapoff swapon switch_root sysctl \
  syslogd tunctl udhcpc udhcpc6 umount vconfig watchdog zcip
do
  ln -sf /bin/busybox "$F/sbin/$x"
done

cp "$T/alpine-keys/etc/apk/keys/"* "$F/etc/apk/keys/"
cp "$T/ca-certificates-bundle/etc/ssl/certs/ca-certificates.crt" "$F/etc/ssl/certs/"
ln -sf certs/ca-certificates.crt "$F/etc/ssl/cert.pem"

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
[ -e /newroot/sbin/boot ] || cp -a /bin /sbin /usr /etc /lib /root /var /newroot/
for d in proc sys dev tmp run mnt/share; do mkdir -p "/newroot/$d"; done
mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
mount --move /dev /newroot/dev
exec switch_root /newroot /sbin/boot
EOF

cat >"$F/sbin/boot" <<'EOF'
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

chmod 755 "$F/init" "$F/sbin/boot" "$F/usr/share/udhcpc/default.script"
(cd "$F"; find . | cpio -o -H newc -R 0:0 2>/dev/null | gzip -9) >initramfs.cpio.gz
ls -lh vmlinuz-virt initramfs.cpio.gz
