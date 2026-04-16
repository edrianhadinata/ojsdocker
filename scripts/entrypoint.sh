#!/bin/bash
set -e

echo "──────────────────────────────────────────"
echo "  OJS Container - PHP 8.4 + Apache2"
echo "──────────────────────────────────────────"

# ─── Set permission direktori penting ─────────────────────────────────────────
echo "[INFO] Setting directory permissions..."
chown -R www-data:www-data /var/www/html/cache /var/www/html/public /var/ojs-files
chmod -R 755 /var/www/html/cache /var/www/html/public /var/ojs-files

# ─── Copy config template jika belum ada ──────────────────────────────────────
if [ ! -f /var/www/html/config.inc.php ]; then
    echo "[INFO] config.inc.php belum ada, menyalin dari template..."
    cp /var/www/html/config.TEMPLATE.inc.php /var/www/html/config.inc.php
    chown www-data:www-data /var/www/html/config.inc.php
fi

# ─── Patch config.inc.php dengan env vars ────────────────────────────────────
if [ ! -z "$DB_HOST" ]; then
    echo "[INFO] Patching config.inc.php dengan konfigurasi database..."
    sed -i "s|^host = .*|host = ${DB_HOST}|g"         /var/www/html/config.inc.php
    sed -i "s|^username = .*|username = ${DB_USER}|g" /var/www/html/config.inc.php
    sed -i "s|^password = .*|password = ${DB_PASSWORD}|g" /var/www/html/config.inc.php
    sed -i "s|^name = .*|name = ${DB_NAME}|g"         /var/www/html/config.inc.php
    sed -i "s|^files_dir = .*|files_dir = /var/ojs-files|g" /var/www/html/config.inc.php
fi

# ─── Setup direktori log supervisor ──────────────────────────────────────────
mkdir -p /var/log/supervisor
mkdir -p /var/log/apache2

# ─── Tambahkan Cron Job OJS (scheduled tasks) ────────────────────────────────
echo "*/5 * * * * www-data php /var/www/html/tools/runScheduledTasks.php /var/www/html/lib/pkp/xml/scheduledTasks.xml >> /var/log/apache2/ojs_cron.log 2>&1" \
    > /etc/cron.d/ojs-scheduled-tasks
chmod 0644 /etc/cron.d/ojs-scheduled-tasks
crontab /etc/cron.d/ojs-scheduled-tasks

echo "[INFO] Container siap! Akses http://${SERVERNAME:-localhost}"
echo "[INFO] Pada instalasi pertama, buka browser dan ikuti wizard OJS."
echo "──────────────────────────────────────────"

# ─── Jalankan Supervisor (Apache + Cron) ─────────────────────────────────────
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
