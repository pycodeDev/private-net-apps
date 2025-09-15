# Private Network + [Windscribe](https://windscribe.com/)

# 📖 Private Net Apps — Instruction & Usage

## 🔹 Apa ini?

`private-net-apps` adalah wrapper CLI sederhana yang mengatur **lingkungan jaringan privat & anonim** berbasis **Windscribe VPN + Tor (dengan dukungan pluggable transport: obfs4 & snowflake) + Proxychains4**.

Di dalamnya tersedia 3 perintah utama:

* `start` → menjalankan `vpn_on.sh` (aktifkan Windscribe, spoof MAC, start Tor (basic/obfs4/snowflake), config proxychains).

  [vpn\_on.sh](https://github.com/pycodeDev/private-net-apps/blob/main/vpn-on.sh)

* `shut` → menjalankan `vpn_off.sh` (disconnect VPN, matikan firewall Windscribe, stop Tor, reset iptables).

  [vpn\_off.sh](https://github.com/pycodeDev/private-net-apps/blob/main/vpn-off.sh)

* `shuffle` → menjalankan `vpn_shuffle.sh` (ganti server VPN secara acak atau rotasi tiap interval).

  [vpn\_shuffle.sh](https://github.com/pycodeDev/private-net-apps/blob/main/vpn-shuffle.sh)

---

## 🔹 Alur Network

### Mode Normal (VPN only)

```
[User/Aplikasi] → [Windscribe VPN Tunnel] → [ISP] → [Internet]
```

* IP publik terlihat = **IP VPN Windscribe**.
* ISP hanya tahu kamu connect ke Windscribe, tujuan akhirnya disembunyikan.

### Mode Proxychains4 (Tor over VPN)

```
[User/Aplikasi] → [Proxychains4] → [Tor local SOCKS (127.0.0.1:9050)]
    → [Tor Circuit: Guard → Middle → Exit]
    → [Windscribe VPN Tunnel] → [ISP] → [Internet]
```

* IP publik terlihat = **Tor Exit Node**, bukan IP VPN.
* ISP hanya tahu kamu connect ke Windscribe, isi di dalam tetap terenkripsi Tor.

### Mode Proxychains4 + Stealth (obfs4 / snowflake)

```
[User/Aplikasi] → [Proxychains4] → [Tor (via obfs4 / snowflake bridges)]
    → [Tor Circuit: Guard → Middle → Exit]
    → [Windscribe VPN Tunnel] → [ISP] → [Internet]
```

* IP publik tetap **Tor Exit Node**.
* Bedanya: jalur masuk ke jaringan Tor **disamarkan** (pakai obfs4 / snowflake).
* ISP/firewall tidak bisa mengenali bahwa kamu sedang menggunakan Tor (lebih sulit diblokir/censored).

---

## 🔹 Flowchart Jalur Koneksi

```bash
flowchart TD
    A[User / App] -->|VPN only| B[VPN Windscribe]
    B --> C[ISP]
    C --> D[Internet]

    A -->|Proxychains4| E[Tor SOCKS5]
    E --> F[Tor Circuit (Guard→Middle→Exit)]
    F --> B

    A -->|Proxychains4 + Stealth| G[Tor via obfs4/snowflake]
    G --> F
```
---

## 🔹 Prasyarat

1. Sudah punya **akun Windscribe** dan sudah login di CLI:

   ```bash
   windscribe-cli login
   ```

2. Sudah install dependency:

   * `windscribe-cli`
   * `tor`
   * `obfs4proxy` *(untuk obfs4)*
   * `snowflake-client` *(opsional, untuk snowflake)*
   * `proxychains4`
   * `macchanger`
   * `iptables`

---

## 🔹 Installation

### 🔸 Menggunakan installer (recommended)

1. Clone repo berisi script.

2. Jalankan installer:

   [install.sh](https://github.com/pycodeDev/private-net-apps/blob/main/install.sh)

   ```bash
   cd private-net-apps
   chmod +x ./install.sh
   sudo ./install.sh
   ```

3. Installer akan:

   * Install dependensi (tor, obfs4proxy, snowflake jika belum ada).
   * Copy `vpn-on.sh`, `vpn-off.sh`, `vpn-shuffle.sh`, dan `private-net-apps` ke `/usr/local/bin/`.
   * Memberikan permission execute.

4. Setelah itu bisa langsung dipanggil:

   ```bash
   private-net-apps start -iface eth0 -level basic
   private-net-apps start -iface wlan0 -level 1        # pakai obfs4
   AUTO_SNOWFLAKE=1 private-net-apps start -level 1    # pakai snowflake
   private-net-apps shut
   private-net-apps shuffle
   ```

---

### 🔸 Tanpa installer (manual)

Kamu juga bisa langsung jalankan script satu per satu:

```bash
# Aktifkan
sudo ./vpn-on.sh

# Gunakan
curl https://ifconfig.me                 # lewat VPN
proxychains4 curl https://ifconfig.me    # lewat Tor/obfs4/snowflake

# Matikan
sudo ./vpn-off.sh
```

---

## 🔹 Penjelasan fitur

1. **MAC Spoofing** → nyamarkan hardware address supaya tidak bisa dilacak di LAN/Wi-Fi.
2. **Windscribe firewall (kill-switch)** → semua trafik non-VPN otomatis diblokir.
3. **Tor + Proxychains4** → jalur tambahan anonimitas untuk aplikasi tertentu.
4. **Stealth mode (obfs4/snowflake)** → buat Tor lebih sulit dideteksi / diblokir ISP.
5. **Shuffle** → ganti server VPN secara acak atau rotasi tiap interval.

---

⚡ Jadi intinya: `private-net-apps` = **one command solution** untuk toggle jaringanmu jadi:

* **VPN only** (cepat, tapi IP = VPN).
* **VPN + Tor (proxychains4)** (anonim, IP = exit node Tor).
* **VPN + Tor + obfs4/snowflake** (anonim + anti-censorship).

