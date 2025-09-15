# Private Network + [Windscribe](https://windscribe.com/)

[![License](https://img.shields.io/github/license/pycodeDev/private-net-apps)](https://github.com/pycodeDev/private-net-apps/blob/main/LICENSE)
[![Stars](https://img.shields.io/github/stars/pycodeDev/private-net-apps?style=social)](https://github.com/pycodeDev/private-net-apps/stargazers)
![Shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)
![Bash](https://img.shields.io/badge/bash-%3E%3D%205.0-blue)

# 📖 Private Net Apps — Instruction & Usage

## 🔹 Apa ini?

`private-net-apps` adalah wrapper CLI sederhana yang mengatur **lingkungan jaringan privat & anonim** berbasis **Windscribe VPN + Tor + Proxychains4**.

Di dalamnya sudah tersedia 3 perintah utama:

- `start` → menjalankan `vpn_on.sh` (aktifkan Windscribe, spoof MAC, start Tor, config proxychains).
    
    [vpn_on.sh](https://github.com/pycodeDev/private-net-apps/blob/main/vpn-on.sh)
    
- `shut` → menjalankan `vpn_off.sh` (disconnect VPN, matikan firewall Windscribe, stop Tor, reset iptables).
    
    [vpn_off.sh](https://github.com/pycodeDev/private-net-apps/blob/main/vpn-off.sh)
    
- `shuffle` → menjalankan `vpn_shuffle.sh` (ganti server VPN secara acak atau rotasi tiap interval).
    
    [vpn_shuffle.sh](https://github.com/pycodeDev/private-net-apps/blob/main/vpn-shuffle.sh)
    

---

## 🔹 Alur Network

### Mode Normal (VPN only)

```
[User/Aplikasi] → [Windscribe VPN Tunnel] → [ISP] → [Internet]
```

- IP publik terlihat = **IP VPN Windscribe**.
- ISP hanya tahu kamu connect ke Windscribe, bukan tujuan akhirnya.

### Mode Proxychains4 (Tor over VPN)

```
[User/Aplikasi] → [Proxychains4] → [Tor local SOCKS (127.0.0.1:9050)]
    → [Tor Circuit: Guard → Middle → Exit]
    → [Windscribe VPN Tunnel] → [ISP] → [Internet]
```

- IP publik terlihat = **Tor Exit Node**, bukan IP VPN.
- ISP hanya tahu kamu connect ke Windscribe → isi di dalamnya tetap terenkripsi Tor.

---

## 🔹 Flowchart Jalur Koneksi

```bash
flowchart TD
    A[User / App] -->|tanpa proxychains4| B[VPN Windscribe]
    B --> C[ISP]
    C --> D[Internet]

    A -->|pakai proxychains4| E[Proxychains4 → Tor SOCKS5]
    E --> F[Tor Circuit (Guard→Middle→Exit)]
    F --> B
```

---

## 🔹 Prasyarat

1. Sudah punya **akun Windscribe** dan sudah login di CLI:
    
    ```bash
    windscribe-cli login
    ```
    
2. Sudah install dependency:
    - `windscribe-cli`
    - `tor`
    - `proxychains4`
    - `macchanger`
    - `iptables`

---

## 🔹 Installation

### 🔸 Menggunakan installer (recommended)

1. Clone/copy repo berisi script.
2. Jalankan installer:
    
    [install.sh](https://github.com/pycodeDev/private-net-apps/blob/main/install.sh)
    
    ```bash
    sudo ./install.sh
    ```
    
3. Installer akan:
    - Copy `vpn-on.sh`, `vpn-off.sh`, `vpn-shuffle.sh`, dan `private-net-apps` wrapper ke `/usr/local/bin/`.
    - Memberikan permission execute.
4. Setelah itu bisa langsung dipanggil:
    
    ```bash
    private-net-apps start
    private-net-apps shut
    private-net-apps shuffle once
    private-net-apps shuffle rotate
    ```
    

---

### 🔸 Tanpa installer (manual)

Kamu juga bisa langsung jalankan script satu per satu:

```bash
# Aktifkan
sudo ./vpn-on.sh

# Gunakan
curl https://ifconfig.me                 # lewat VPN
proxychains4 curl https://ifconfig.me    # lewat Tor di atas VPN

# Matikan
sudo ./vpn-off.sh
```

---

## 🔹 Penjelasan fitur

1. **MAC Spoofing** → nyamarkan hardware address supaya tidak bisa dilacak di LAN/Wi-Fi.
2. **Windscribe firewall (kill-switch)** → semua trafik non-VPN otomatis diblokir.
3. **Tor + Proxychains4** → jalur tambahan anonimitas untuk aplikasi tertentu.
4. **Shuffle** → ganti server VPN secara acak atau rotasi tiap interval.

---

⚡ Jadi intinya: `private-net-apps` = **one command solution** untuk toggle jaringanmu jadi **VPN only** atau **VPN+Tor (proxychains4)** dengan opsi shuffle server otomatis.
