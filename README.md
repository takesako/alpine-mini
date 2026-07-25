# alpine-mini
A tiny Alpine Linux environment for QEMU with initramfs, persistent rootfs, 9P sharing, and minimal dependencies.

最小構成の Alpine Linux を QEMU 上で起動するためのスクリプトです。

initramfs と BusyBox のみで起動し、初回起動時に永続ディスクへルートファイルシステムを展開します。
演習環境用途を想定し、できるだけシンプルな構成で高速な起動を目指しています。

## 特徴

* Alpine Linux ベース
* BusyBox のみを利用した最小ユーザーランド
* initramfs から起動
* 初回起動時のみルートファイルシステムを永続ディスクへコピー(仕様変更可能性あり)
* root.qcow2 に永続保存
* swap.qcow2 にスワップ領域
* 9P によるホストとのフォルダー共有
* DHCP によるネットワーク設定

## 必要環境

* macOS の場合

```sh
brew install qemu e2fsprogs zstd cpio
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

## 起動

```sh
./run.sh
```

初回起動時のみ

* `root.qcow2`
* `swap.qcow2`

が自動生成されます。

## 動作確認済みOS

2026-07-25 に以下の環境で起動を確認しました。

* ホスト: macOS 26.5.2 (arm64)
* ゲスト: Alpine Linux v3.24 (x86_64)
* ゲストカーネル: Linux 6.18.39-0-virt
* QEMU: 11.0.1

ゲスト内では以下のディスク構成を確認しました。

* `/dev/vda`: ext4、`/` にマウント、3.9 GiB
* `share`: 9P、`/mnt/share` にマウント
* `/dev/vdb`: swap、1.0 GiB

確認後はファイルシステムを同期して電源断し、QEMU が正常に終了することを確認しました。

## ホストとの共有

ホスト側

```
share/
```

ゲスト側

```
/mnt/share
```

## ディレクトリ構成

```
.
├── build.sh
├── run.sh
├── packages/
├── rootfs/
├── share/
├── initramfs.cpio.gz
├── vmlinuz-virt
├── root.qcow2
└── swap.qcow2
```
