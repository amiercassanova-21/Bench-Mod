# Bench-Mod

Speedtest VPS ke server **operator kartu seluler Indonesia** (Telkomsel, Indosat, XL) dan **Singapura**, dengan tampilan rapi yang aman untuk terminal HP.

<p align="center"><img src="hasil.png" alt="Contoh hasil Bench-Mod (mode Lengkap)" width="460"></p>

<p align="center"><sub>Contoh tampilan mode <b>Lengkap</b>. Angka di gambar hanya contoh, hasil asli tergantung VPS.</sub></p>

## Cara pakai

Bisa dijalankan di **VPS mana pun**, tidak perlu memasang SC apa pun.

**Pilih mode dari menu:**
```bash
bash <(curl -sSL https://raw.githubusercontent.com/amiercassanova-21/Bench-Mod/main/bench.sh)
```

**Atau dengan curl lalu bash:**
```bash
curl -sS -H 'Cache-Control: no-cache, no-store' https://raw.githubusercontent.com/amiercassanova-21/Bench-Mod/main/bench.sh | bash
```

**Langsung ke mode tertentu** (tanpa menu):
```bash
curl -sS -H 'Cache-Control: no-cache, no-store' https://raw.githubusercontent.com/amiercassanova-21/Bench-Mod/main/bench.sh | bash -s lengkap
```
Ganti `lengkap` dengan salah satu mode di bawah.

## Mode

| Mode | Isi tes | Waktu |
|---|---|---|
| `cepat` | Server terdekat + 1 server tiap operator (Jakarta, atau SG bila VPS di Singapura) | ±2 menit |
| `id` | Semua kota operator di Indonesia | ±5 menit |
| `sg` | Server Singapura tiap operator | ±2 menit |
| `lengkap` | Semua server (server di negara VPS dites lebih dulu) | ±6 menit |
| `<id server>` | Satu server Speedtest pilihan, contoh `bash -s 71028` | ±30 detik |
| `disk` | Uji tulis disk 512 MB (ada konfirmasi dulu) | ±10 detik |

## Daftar server

| Operator | Kota |
|---|---|
| ● Telkomsel | Jakarta, Surabaya, Medan, Batam, Telin SG |
| ● Indosat | Jakarta, Surabaya, Medan, Batam, SG |
| ● XL Axiata | Jakarta, Surabaya, Medan, SG |

Hanya operator kartu seluler. Smartfren sudah bergabung ke XL, dan layanan WiFi rumahan tidak dimasukkan.

Daftar server ada di [`speedtest-servers.txt`](speedtest-servers.txt) dan diambil ulang setiap tes. Kalau ada server yang mati, cukup ganti ID-nya di file itu, tanpa mengubah `bench.sh`. Server yang tidak menjawab ditandai `! server tidak aktif · dilewati`.

Format tiap baris: `OPERATOR|Kota|ID atau SG|ID server Ookla`

## Yang ditampilkan
- Info VPS: kota, ISP, negara, CPU, RAM, disk, OS
- Download, upload, dan ping tiap server. Bar kecepatan dibandingkan dengan server tercepat. Warna ping: hijau di bawah 30 ms, kuning di bawah 80 ms, merah di atasnya
- Ringkasan: server tercepat, rata-rata ping ke Indonesia, kecocokan (Game, Stream, Call), dan server yang gagal
- Riwayat 10 tes terakhir di `~/.bench-mod/history`

## Catatan
- Memakai **Speedtest CLI resmi Ookla 1.2.0**. File diunduh sekali ke `~/.bench-mod/` dan dicek SHA-256 sebelum dipakai.
- Mendukung `x86_64` dan `aarch64` (ARM). Diuji di Ubuntu dan Debian.
- Selama tes, bandwidth VPS terpakai penuh. Pengguna lain di VPS itu bisa melambat sebentar.
- Info lokasi VPS diambil dari ipwho.is (cadangan: ip-api.com).

## Kredit
- **Base:** [bench.sh](https://github.com/teddysun/across) by **Teddysun**
- **Mod:** **Cassanova Tunneling**
- Speedtest CLI © Ookla. Pemakaian tunduk pada lisensi Ookla.
