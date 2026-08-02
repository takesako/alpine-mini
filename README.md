# alpine-mini

A tiny Alpine Linux environment for QEMU with a minimal initramfs, a read-only
SquashFS userland, a persistent OverlayFS, swap, and VVFAT host sharing.

最小構成の Alpine Linux を QEMU 上で起動するためのスクリプトです。

小さな initramfs から起動し、読み取り専用の Alpine ユーザーランド
`root.squashfs` に、書き込み可能な `overlay.qcow2` を OverlayFS として重ねます。
演習・検証用途を想定し、構成を単純に保ちながら、パッケージ追加、永続化、
ホストとのファイル共有、USB パススルーを利用できるようにしています。

## 特徴

- Alpine Linux v3.24、x86_64 ゲスト
- BusyBox、起動用カーネルモジュール、`/init` のみを含む最小 initramfs
- Alpine ユーザーランドを圧縮した読み取り専用 `root.squashfs`
- OverlayFS による書き込み可能なルートファイルシステム
- `overlay.qcow2` への変更内容の永続保存
- `/lib/apk/db` を収録し、ゲスト上の `apk add` に対応
- `swap.qcow2` によるスワップ領域
- QEMU VVFAT によるホストとのファイル共有
- DHCP をバックグラウンドで実行
- VirtIO Console (`hvc0`) を標準コンソールとして使用
- QEMU monitor を TCP `127.0.0.1:4444` で提供
- ホストの TCP 7777、8888 をゲストの同じポートへ転送
- USB デバイス `04b4:8613`、`16d0:0753` のパススルー設定
- 一般ユーザー `user` で自動ログイン
- `wheel` グループからパスワードなしで `doas` を使用可能
- 一般ユーザーから ICMP ping を実行可能

## 起動構成

```text
QEMU
 ├── img/vmlinuz-virt
 ├── img/initramfs.cpio.gz
 ├── /dev/vda  img/root.squashfs       読み取り専用 lower layer
 ├── /dev/vdb  disk/overlay.qcow2      ext4 upper/work layer
 ├── /dev/vdc  disk/swap.qcow2         swap
 └── /dev/vdd1 vfat/                   VVFAT共有
```

initramfs は `/dev/vda` と `/dev/vdb` を組み合わせて OverlayFS を構成し、
`switch_root` で Alpine ユーザーランドの `/sbin/boot` を実行します。

## ファイル構成

```text
.
├── build.sh                 カーネル、initramfs、rootfsの生成
├── disk.sh                  overlay・swapディスクの再作成
├── run.sh                   macOS・Unix系ホスト用の起動スクリプト
├── run.bat                  Windows用の起動スクリプト
├── img/
│   ├── initramfs.cpio.gz
│   ├── root.squashfs
│   └── vmlinuz-virt
├── disk/
│   ├── overlay.qcow2
│   └── swap.qcow2
├── tmp/
│   ├── initramfs-root/
│   ├── packages/
│   └── rootfs/
├── vfat/                    ホスト・ゲスト共有フォルダー
└── qemu-log                 QEMUの標準エラー出力
```

`tmp/packages/` に取得済み APK を保存するため、同じバージョンの再ビルドでは
パッケージを再利用します。

## 必要環境

### ビルド時

`build.sh` は次のコマンドを使用します。

```text
sh curl tar cpio gzip mksquashfs zstd
```

### ディスク作成時

`disk.sh` は次のコマンドを使用します。

```text
qemu-img truncate mkfs.ext4
```

### 起動時

```text
qemu-system-x86_64
```

### macOS

Homebrewを使用する場合の例です。

```sh
brew install qemu e2fsprogs squashfs zstd cpio coreutils
```

Homebrew版 coreutils のコマンドを利用する場合は、`truncate` が見つかるように
GNU coreutils の `gnubin` を `PATH` に追加してください。

```sh
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
```

`disk.sh` は `mkfs.ext4` が通常の `PATH` にない場合、Homebrewの
`e2fsprogs` 配下も自動的に検索します。

### Windows

`run.bat` を使用するには、`qemu-system-x86_64.exe` が `PATH` に必要です。
Windows版は `WHPX` を優先し、利用できない場合は `TCG` へフォールバックします。

`build.sh` と `disk.sh` はPOSIXシェル用です。Windowsだけで使用する場合は、
WSLなどで生成するか、別環境で作成した `img/` と `disk/` を配置してください。

## ビルド

```sh
chmod +x build.sh disk.sh run.sh
./build.sh
```

次のファイルが `img/` に生成されます。

```text
img/vmlinuz-virt
img/initramfs.cpio.gz
img/root.squashfs
```

`build.sh` は Alpine v3.24 のリポジトリから、その時点の最新パッケージを取得します。
そのため、生成されるカーネルの詳細バージョンは更新時期によって変わります。

## ディスク作成

```sh
./disk.sh
```

次のディスクが `disk/` に生成されます。

| ファイル | 既定の仮想容量 | 用途 |
| --- | ---: | --- |
| `overlay.qcow2` | 8 GiB | OverlayFS の upper/work layer |
| `swap.qcow2` | 2 GiB | スワップ領域 |

容量は環境変数で変更できます。

```sh
OVERLAY_SIZE=16G SWAP_SIZE=4G ./disk.sh
```

> [!WARNING]
> `disk.sh` は既存の `disk/overlay.qcow2` と `disk/swap.qcow2` を削除してから
> 再作成します。ゲスト上で追加したパッケージや作成したファイルも失われます。

## 起動

### macOS・Unix系ホスト

```sh
./run.sh
```

### Windows

```bat
run.bat
```

既定のメモリー容量は128 MiBです。

`run.sh` と `run.bat` はQEMUの標準エラーを `qemu-log` に保存します。
USBパススルーなどの問題を確認する場合は、次を参照してください。

```sh
cat qemu-log
```

## ログインと権限

起動後は、次の一般ユーザーで自動ログインします。

```text
ユーザー名: user
UID:        1000
主グループ: users (GID 100)
補助グループ: wheel
ホーム:     /home/user
シェル:     /bin/sh
```

`wheel` グループにはパスワードなしの `doas` が許可されています。

```sh
doas apk update
doas apk add strace
```

`busybox-suid` により、`mount`、`umount`、`su`、`crontab`、`passwd`、
`traceroute`、`traceroute6`、`vlock` は必要な権限で実行されます。

一般ユーザーからの ICMP ping も許可されています。

```sh
ping 8.8.8.8
```

## ネットワーク

QEMUのユーザーモードネットワークを使用します。ゲストは通常、DHCPで
`10.0.2.15` を取得します。

DHCPはバックグラウンドで実行するため、ログイン直後はまだアドレスを取得して
いない場合があります。

```sh
ip addr show eth0
ip route
```

現行の起動スクリプトでは、次のTCPポートをローカルホストへ転送します。

```text
ホスト 127.0.0.1:7777 -> ゲスト :7777
ホスト 127.0.0.1:8888 -> ゲスト :8888
```

ゲスト側のサーバーは `127.0.0.1` ではなく、`0.0.0.0` またはゲストの
インターフェースアドレスで待ち受けてください。

## QEMU monitor

QEMU monitorはゲストコンソールと分離し、TCPポート4444で待ち受けます。

macOS・Unix系ホストから接続する例：

```sh
nc 127.0.0.1 4444
```

WindowsではTelnetクライアントやNcatなどを使用できます。

```text
info status
info usbhost
info usb
quit
```

## USBパススルー

現行の `run.sh` と `run.bat` は、xHCIコントローラーを作成し、次のUSB IDを
ゲストへ接続しようとします。

```text
04b4:8613
16d0:0753
```

接続対象がホストに存在しない場合や、QEMUからデバイスを開けない場合は、
`qemu-log` とQEMU monitorの `info usbhost`、`info usb` を確認してください。

USB IDを変更する場合は、`run.sh` と `run.bat` の次の設定を編集します。

```text
-device usb-host,vendorid=0x04b4,productid=0x8613
-device usb-host,vendorid=0x16d0,productid=0x0753
```

## ホストとのファイル共有

ホスト側の `vfat/` を、ゲスト側の `/vfat` にQEMU VVFATとしてマウントします。

```text
ホスト: vfat/
ゲスト: /vfat
        /home/user/vfat -> /vfat
```

ゲストではUID 1000、GID 100の所有物として見えます。

```sh
ls -la /vfat
```

時刻差を避けるため、QEMUプロセスには `TZ=UTC0` を設定し、ゲストでは
`tz=UTC` を指定してマウントします。

## ゲスト内のディスク構成

| デバイス | ファイル | 用途 |
| --- | --- | --- |
| `/dev/vda` | `img/root.squashfs` | 読み取り専用 lower layer |
| `/dev/vdb` | `disk/overlay.qcow2` | ext4 upper/work layer |
| `/dev/vdc` | `disk/swap.qcow2` | swap |
| `/dev/vdd1` | `vfat/` | `/vfat` への共有領域 |

OverlayFSの下層・上層はゲストの `/overlay` から確認できます。

```sh
mount
df -h
swapon --show
```

## 永続化と初期化

`apk add`、設定変更、ホームディレクトリの内容など、ルートファイルシステムへの
変更は `disk/overlay.qcow2` に保存されます。

`build.sh` を再実行して `root.squashfs` を更新しても、既存の
`overlay.qcow2` は変更されません。ただし、古いlower layerを前提とした
upper layerとの組み合わせには注意してください。

完全に初期化する場合は、QEMUを終了してから `disk.sh` を再実行します。

```sh
./disk.sh
```

## 終了

ゲストから終了します。

```sh
poweroff
```

一般ユーザーから実行した場合は、`doas` を経由して同期、`/vfat` のアンマウント、
OverlayFSディスクの `fstrim` を行ってから電源を切ります。

ログインシェルから `exit` した場合も、起動スクリプトが `poweroff` を実行します。

