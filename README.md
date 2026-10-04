<p align="center">
  <img src="docs/banner.jpg" alt="NightPanel Installer" width="100%">
</p>

<h1 align="center">🌙 NightPanel Installer</h1>

<p align="center">
  Installer Pterodactyl Panel &amp; Wings dengan tampilan malam yang tenang.<br>
  Sambutan personal, menu bertombol, satu perintah langsung jalan.
</p>

<p align="center">
  <a href="https://github.com/Fahridev1/pterodactyl-free-theme"><img alt="Repo" src="https://img.shields.io/badge/GitHub-Repo-1f2a5a?style=for-the-badge&logo=github&logoColor=white"></a>
  <a href="#cara-pakai"><img alt="Install" src="https://img.shields.io/badge/Install-Sekarang-e8a33d?style=for-the-badge&logo=gnubash&logoColor=white"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPLv3-3b5bdb?style=for-the-badge"></a>
</p>

## ✨ Fitur

- Pop up sambutan: **"Hai, selamat datang @username!"** (dialog `whiptail`, fallback kotak di terminal).
- Seluruh proses instalasi **berbahasa Indonesia**: pertanyaan, peringatan, pesan error, dan ringkasan.
- Tampilan terminal bertema malam: menu bertombol, langkah ▸ / ✔ / ✘, ringkasan konfigurasi rapi, dan kotak penutup.
- Instalasi otomatis Panel (dependensi, database, cronjob, nginx) dan Wings (Docker, systemd).
- Opsional: Let's Encrypt dan firewall otomatis.
- Uninstall Panel dan Wings.

## 🚀 Cara pakai

Jalankan sebagai root:

```bash
bash <(curl -s https://raw.githubusercontent.com/Fahridev1/pterodactyl-free-theme/master/install.sh)
```

Lewati pertanyaan username:

```bash
INSTALLER_USER=fahri bash <(curl -s https://raw.githubusercontent.com/Fahridev1/pterodactyl-free-theme/master/install.sh)
```

## 🌌 Tema web Panel

Menu **"Pasang / hapus tema Night"** di installer memasang tema malam ke Panel yang sudah terinstall:

- Latar gambar malam di semua halaman (login, dashboard, server) dengan efek kaca transparan.
- Tombol dengan gradasi warna, input dan kartu yang lebih halus.
- Pop up **"Hai, selamat datang @username!"** sekali per sesi setelah login.

Tema juga ditawarkan otomatis di akhir instalasi Panel. Update Pterodactyl akan menimpa `wrapper.blade.php`, jadi jalankan menu tema lagi setelah update. Pilih menu hapus untuk kembali ke tampilan asli.

## 🏷️ Ganti nama / repo

```bash
./rename.sh "Nama Baru" github-username nama-repo
```

Script ini mengganti nama brand, log path, dan semua URL raw GitHub sekaligus. Setelah itu push ke repo kamu (branch `master`).

## Supported installations

List of supported installation setups for panel and Wings (installations supported by this installation script).

### Supported panel and wings operating systems

| Operating System | Version | Supported          | PHP Version |
| ---------------- | ------- | ------------------ | ----------- |
| Ubuntu           | 14.04   | :red_circle:       |             |
|                  | 16.04   | :red_circle: \*    |             |
|                  | 18.04   | :red_circle: \*    |             |
|                  | 20.04   | :red_circle: \*    |             |
|                  | 22.04   | :white_check_mark: | 8.3         |
|                  | 24.04   | :white_check_mark: | 8.3         |
|                  | 26.04   | :white_check_mark: | 8.3         |
| Debian           | 8       | :red_circle: \*    |             |
|                  | 9       | :red_circle: \*    |             |
|                  | 10      | :white_check_mark: | 8.3         |
|                  | 11      | :white_check_mark: | 8.3         |
|                  | 12      | :white_check_mark: | 8.3         |
|                  | 13      | :white_check_mark: | 8.3         |
| CentOS           | 6       | :red_circle:       |             |
|                  | 7       | :red_circle: \*    |             |
|                  | 8       | :red_circle: \*    |             |
| Rocky Linux      | 8       | :white_check_mark: | 8.3         |
|                  | 9       | :white_check_mark: | 8.3         |
| AlmaLinux        | 8       | :white_check_mark: | 8.3         |
|                  | 9       | :white_check_mark: | 8.3         |

_\* Indicates an operating system and release that previously was supported by this script._

## Using the installation scripts

To use the installation scripts, simply run this command as root. The script will ask you whether you would like to install just the panel, just Wings or both.

```bash
bash <(curl -s https://raw.githubusercontent.com/Fahridev1/pterodactyl-free-theme/master/install.sh)
```

_Note: On some systems, it's required to be already logged in as root before executing the one-line command (where `sudo` is in front of the command does not work)._

Here is a [YouTube video](https://www.youtube.com/watch?v=E8UJhyUFoHM) that illustrates the installation process.

## Firewall setup

The installation scripts can install and configure a firewall for you. The script will ask whether you want this or not. It is highly recommended to opt-in for the automatic firewall setup.

## Development & Ops

### Testing the script locally

To test the script, we use [Vagrant](https://www.vagrantup.com). With Vagrant, you can quickly get a fresh machine up and running to test the script.

If you want to test the script on all supported installations in one go, just run the following.

```bash
vagrant up
```

If you only want to test a specific distribution, you can run the following.

```bash
vagrant up <name>
```

Replace name with one of the following (supported installations).

- `ubuntu_jammy`
- `debian_bullseye`
- `debian_buster`
- `debian_bookworm`
- `debian_trixie`
- `almalinux_8`
- `almalinux_9`
- `rockylinux_8`
- `rockylinux_9`

Then you can use `vagrant ssh <name of machine>` to SSH into the box. The project directory will be mounted in `/vagrant` so you can quickly modify the script locally and then test the changes by running the script from `/vagrant/installers/panel.sh` and `/vagrant/installers/wings.sh` respectively.

### Creating a release

In `install.sh` github source and script release variables should change every release. Firstly, update the `CHANGELOG.md` so that the release date and release tag are both displayed. No changes should be made to the changelog points themselves. Secondly, update `GITHUB_SOURCE` and `SCRIPT_RELEASE` in `install.sh`. Finally, you can now push a commit with the message `Release vX.Y.Z`. Create a release on GitHub. See [this commit](https://github.com/pterodactyl-installer/pterodactyl-installer/commit/90aaae10785f1032fdf90b216a4a8d8ca64e6d44) for reference.

## Credits & lisensi

Fork dari [pterodactyl-installer](https://github.com/pterodactyl-installer/pterodactyl-installer) oleh Vilhelm Prytz, dirawat oleh Linux123123 dan kontributor. Dilisensikan di bawah GPLv3 (lihat `LICENSE`).

Copyright (C) 2018 - 2026, Vilhelm Prytz, <vilhelm@prytznet.se>, and contributors.

Script ini tidak berafiliasi dengan [Pterodactyl Project](https://pterodactyl.io/) resmi.
