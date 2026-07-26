# alpine-mini
A tiny Alpine Linux environment for QEMU with a minimal initramfs, a
read-only SquashFS userland, a persistent OverlayFS, and VVFAT sharing.

最小構成の Alpine Linux を QEMU 上で起動するためのスクリプトです。

最小構成の initramfs で起動し、読み取り専用の Alpine ユーザーランドへ
永続ディスクの書き込みレイヤーを重ねます。
演習環境用途を想定し、できるだけシンプルな構成で高速な起動を目指しています。

## 特徴

* Alpine Linux ベース
* BusyBox、カーネルモジュール、`/init` のみの最小 initramfs
* Alpine ユーザーランドを圧縮した読み取り専用 `root.squashfs`
* `/lib/apk/db` を収録し、OverlayFS 上で `apk add` に対応
* OverlayFS によるルートファイルシステム
* `overlay.qcow2` に変更内容を永続保存
* swap.qcow2 にスワップ領域
* VVFAT によるホストとのフォルダー同期
* DHCP によるネットワーク設定

## イメージ構成

| イメージ | 役割 | 参考サイズ |
| --- | --- | ---: |
| `initramfs.cpio.gz` | BusyBox、起動用モジュール、`/init` | 約 2.4 MiB |
| `root.squashfs` | 最小 Alpine ユーザーランドの読み取り専用 lower layer | 約 3.6 MiB |
| `overlay.qcow2` | OverlayFS の書き込み可能な upper/work layer | 初回作成時は約 1 MiB |

`root.squashfs` を再ビルドしても `overlay.qcow2` は維持されるため、
ユーザーランドと永続データを独立して扱えます。完全に初期化する場合は、
QEMU を終了してから `overlay.qcow2` を削除してください。

## 必要環境

* macOS の場合

```sh
brew install qemu e2fsprogs squashfs zstd cpio
```

`mkfs.ext4` が PATH に存在することを確認してください。

$(brew --prefix e2fsprogs)/sbin/mkfs.ext4

## ビルド

```sh
./build.sh
```

以下のファイルが生成されます。

* `vmlinuz-virt`
* `initramfs.cpio.gz`
* `root.squashfs`

## 起動

```sh
./run.sh
```

初回起動時のみ

* `overlay.qcow2`
* `swap.qcow2`

が自動生成されます。

既定ではホスト側ポートの転送と USB パススルーを行いません。必要な場合は
環境変数で有効化できます。

```sh
SSH_PORT=2222 USB_PASSTHROUGH=1 ./run.sh
```

容量とメモリーは `OVERLAY_SIZE`、`SWAP_SIZE`、`MEMORY` で変更できます。

## 動作確認済みOS

2026-07-25 に以下の環境で起動を確認しました。

* ホスト: macOS 26.5.2 (arm64)
* ゲスト: Alpine Linux v3.24 (x86_64)
* ゲストカーネル: Linux 6.18.39-0-virt
* QEMU: 11.0.1

ゲスト内では以下のディスク構成を確認しました。

* `/dev/vda`: SquashFS、読み取り専用 lower layer
* `/dev/vdb`: ext4、OverlayFS の upper/work layer、4.0 GiB
* `overlay`: `/` にマウント
* `/dev/vdc`: swap、1.0 GiB
* `/dev/vdd1`: vfat、`/vfat` に `rw,sync,dirsync` でマウント

確認後はファイルシステムを同期して電源断し、QEMU が正常に終了することを確認しました。

## ホストとの同期

ホスト側

```
vfat/
```

ゲスト側

```
/vfat
```

## ディレクトリ構成

```
.
├── build.sh
├── run.sh
├── img/
│   ├── initramfs.cpio.gz
│   ├── overlay.qcow2
│   ├── root.squashfs
│   ├── swap.qcow2
│   └── vmlinuz-virt
├── tmp/
│   ├── initramfs-root/
│   ├── packages/
│   └── rootfs/
└── vfat/
```
