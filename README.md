<div align="center">
  <h1>🚀 DNSDist One-Click Installer + Komdigi Filter</h1>
  <p>
    <strong>Cara super cepat, ringan, dan praktis menginstal DNS Server menggunakan <a href="https://dnsdist.org/">dnsdist</a> lengkap dengan fitur pemblokiran situs Trust Positif (Internet Positif) dari Komdigi.</strong>
  </p>
</div>

---

## ✨ Fitur Utama

- ⚡ **Sangat Cepat & Ringan**: Menggunakan `dnsdist` sebagai loadbalancer/router DNS yang sudah terpercaya akan kecepatannya.
- 🛡️ **Built-in Komdigi Blocklist**: Secara otomatis mengambil dan menerapkan daftar blokir *Trust Positif* (Internet Positif) dari Kementerian Komunikasi dan Digital (Komdigi).
- 🗄️ **Performa Maksimal dengan CDB**: Mengakali jumlah *blocklist* yang sangat besar dengan mengubahnya menjadi format *Constant Database (CDB)* menggunakan `freecdb` sehingga lookup domain terlarang terjadi dalam waktu $O(1)$ tanpa memakan banyak memori.
- 🔄 **Auto-Update Blocklist**: Disediakan skrip terpisah (`update-blocklist.sh`) untuk memperbarui daftar situs terlarang kapan saja.
- 🚦 **Dua Mode Pemblokiran**:
  - **NXDOMAIN**: Langsung menolak akses (Domain Not Found).
  - **Web Server Redirect**: Mengalihkan *user* ke IP Web Server khusus (misal: halaman pemberitahuan blokir).

## 📋 Prasyarat Sistem

1. Sistem Operasi Ubuntu 22.04 atau terbaru LTS (untuk penggunaan `apt`).
2. Akses user **root** atau `sudo`.
3. Port **53 (UDP & TCP)** tidak terpakai/terbuka di *firewall*.

## 🛠️ Cara Instalasi

1. Unduh script ke dalam *server* Anda:
   ```bash
   curl -O https://raw.githubusercontent.com/azhrimzdi/dnsdist-one-click/main/install-dns.sh
   ```
   *(Atau Anda bisa menggunakan `wget` atau clone repositori ini)*

2. Berikan izin eksekusi pada *script*:
   ```bash
   chmod +x install-dns.sh
   ```

3. Jalankan *script* dengan izin **root**:
   ```bash
   sudo ./install-dns.sh
   ```

4. Ikuti panduan interaktif yang muncul di layar:
   - Masukkan **IP Server** yang akan digunakan.
   - Masukkan **IP / Subnet Client** untuk ACL (agar *client* diizinkan *query* DNS).
   - Pilih mode blokir (*NXDOMAIN* atau *Redirect IP*).

## 🔄 Cara Update Blocklist
Setelah *script* instalasi selesai, folder `/opt/blocklist` akan otomatis dibuat. 
Bila sewaktu-waktu terdapat pembaruan dari Komdigi, perbarui basis data *blocklist* Anda menggunakan perintah ini:

```bash
sudo bash /opt/blocklist/update-blocklist.sh
```
*Tips: Anda dapat menambahkan *command* ini ke dalam `crontab` agar pembaruan *blocklist* berjalan otomatis setiap hari!*

## 📁 Struktur Direktori
- `/etc/dnsdist/dnsdist.conf`: File konfigurasi utama dari `dnsdist`
- `/opt/blocklist/`: Folder kerja *blocklist* Trust Positif
- `/opt/blocklist/update-blocklist.sh`: Skrip pembaruan otomatis
- `/opt/blocklist/domains.cdb`: Basis data nama domain dalam format CDB.

## 🤝 Berkontribusi
Masukan (Feedback), *Issue*, dan *Pull Request* selalu dipersilakan. Mari buat ekosistem DNS Indonesia yang lebih efisien dan modern!
