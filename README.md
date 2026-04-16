# 🐳 OJS Docker — Apache2 + PHP 8.4 + MySQL 8.0

Konfigurasi Docker siap pakai untuk Open Journal Systems (OJS) menggunakan
**Apache2**, **PHP 8.4**, dan **MySQL 8.0**.

---

## 📁 Struktur File

```
ojs-docker/
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── config/
│   ├── ojs.conf          # Apache VirtualHost
│   ├── php.ini           # Konfigurasi PHP
│   ├── mysql.cnf         # Konfigurasi MySQL
│   └── supervisord.conf  # Supervisord (Apache + Cron)
├── scripts/
│   └── entrypoint.sh     # Skrip startup container
└── logs/
    └── apache/           # Log Apache (auto dibuat)
```

---

## 🚀 Cara Menjalankan

### 1. Clone & Persiapan

```bash
git clone <repo-kamu>
cd ojs-docker
cp .env.example .env
```

### 2. Edit file `.env`

```env
SERVERNAME=localhost
HTTP_PORT=8080
DB_NAME=ojs
DB_USER=ojs
DB_PASSWORD=password_kuat_kamu
DB_ROOT_PASSWORD=root_password_kuat
```

### 3. Build & Jalankan

```bash
docker compose up -d --build
```

> Build pertama membutuhkan waktu beberapa menit karena mengunduh OJS.

### 4. Cek status container

```bash
docker compose ps
docker compose logs -f ojs_app
```

### 5. Buka Browser

| Service     | URL                        |
|-------------|----------------------------|
| OJS         | http://localhost:8080      |
| phpMyAdmin  | http://localhost:8081      |

---

## 🔧 Pengaturan Instalasi OJS (Wizard)

Saat pertama kali membuka OJS di browser, isi formulir instalasi dengan:

| Field           | Nilai              |
|-----------------|--------------------|
| Database Driver | `mysqli`           |
| Host            | `ojs_db`           |
| Username        | nilai `DB_USER`    |
| Password        | nilai `DB_PASSWORD`|
| Database Name   | nilai `DB_NAME`    |
| Files Directory | `/var/ojs-files`   |

---

## 🗂️ Volume Persisten

| Volume        | Deskripsi                        |
|---------------|----------------------------------|
| `ojs_db_data` | Data MySQL                       |
| `ojs_files`   | File upload artikel/jurnal       |
| `ojs_public`  | Gambar publik OJS                |
| `ojs_cache`   | Cache OJS                        |

---

## 🔒 Setelah Instalasi — Simpan config.inc.php

```bash
# Salin config.inc.php dari container ke lokal
docker cp ojs_app:/var/www/html/config.inc.php ./volumes/config/config.inc.php
```

Lalu uncomment baris ini di `docker-compose.yml`:
```yaml
# - ./volumes/config/config.inc.php:/var/www/html/config.inc.php
```

---

## 🛠️ Perintah Berguna

```bash
# Masuk ke container OJS
docker exec -it ojs_app bash

# Cek log PHP
docker exec ojs_app tail -f /var/log/apache2/php_errors.log

# Restart Apache di dalam container
docker exec ojs_app apachectl restart

# Backup database
docker exec ojs_db mysqldump -u ojs -pojspassword ojs > backup_ojs.sql

# Restore database
docker exec -i ojs_db mysql -u ojs -pojspassword ojs < backup_ojs.sql

# Hentikan semua container
docker compose down

# Hapus semua termasuk volume (HATI-HATI: data hilang!)
docker compose down -v
```

---

## ⚠️ Catatan Penting

- PHP 8.4 kompatibel penuh dengan **OJS 3.4.x ke atas**
- Untuk OJS 3.3.x, gunakan **PHP 8.0–8.1** jika ada plugin yang tidak kompatibel
- `php -S` **tidak** digunakan di Docker; Apache menggantikan peran tersebut
- Container ini **tidak untuk produksi langsung** tanpa konfigurasi SSL/HTTPS tambahan
