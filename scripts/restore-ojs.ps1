$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

param(
    [Parameter(Mandatory = $true)]
    [string]$BackupDir
)

function Get-DotEnvValue {
    param(
        [hashtable]$EnvMap,
        [string]$Name,
        [string]$DefaultValue
    )

    if ($EnvMap.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace($EnvMap[$Name])) {
        return $EnvMap[$Name]
    }

    return $DefaultValue
}

if (-not (Test-Path $BackupDir)) {
    throw "Folder backup tidak ditemukan: $BackupDir"
}

$dbFile = Join-Path $BackupDir "db.sql"
$publicTar = Join-Path $BackupDir "public.tar.gz"
$cacheTar = Join-Path $BackupDir "cache.tar.gz"
$filesTar = Join-Path $BackupDir "files.tar.gz"
$configFile = Join-Path $BackupDir "config.inc.php"

if (-not (Test-Path $dbFile)) {
    throw "File wajib db.sql tidak ditemukan di $BackupDir"
}
if (-not (Test-Path $publicTar)) {
    throw "File wajib public.tar.gz tidak ditemukan di $BackupDir"
}

Write-Host "[INFO] Validasi Docker Compose..."
docker compose version | Out-Null

$runningServices = docker compose ps --status running --services
if ($runningServices -notcontains "ojs_db" -or $runningServices -notcontains "ojs_app") {
    throw "Service ojs_db dan ojs_app harus dalam status running. Jalankan: docker compose up -d"
}

$envMap = @{}
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
            return
        }

        $parts = $line.Split("=", 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"')
        $envMap[$key] = $value
    }
}

$dbUser = Get-DotEnvValue -EnvMap $envMap -Name "DB_USER" -DefaultValue "ojs"
$dbPassword = Get-DotEnvValue -EnvMap $envMap -Name "DB_PASSWORD" -DefaultValue "ojspassword"
$dbName = Get-DotEnvValue -EnvMap $envMap -Name "DB_NAME" -DefaultValue "ojs"

Write-Host "[INFO] Restore database <- db.sql"
docker compose cp "$dbFile" "ojs_db:/tmp/ojs_restore.sql" | Out-Null
docker compose exec -T ojs_db sh -lc "mysql -u'$dbUser' -p'$dbPassword' '$dbName' < /tmp/ojs_restore.sql"
docker compose exec -T ojs_db sh -lc "rm -f /tmp/ojs_restore.sql"

Write-Host "[INFO] Restore public files <- public.tar.gz"
docker compose cp "$publicTar" "ojs_app:/tmp/ojs_public.tar.gz" | Out-Null
docker compose exec -T ojs_app sh -lc "mkdir -p /var/www/html/public; find /var/www/html/public -mindepth 1 -delete; tar xzf /tmp/ojs_public.tar.gz -C /var/www/html/public"
docker compose exec -T ojs_app sh -lc "rm -f /tmp/ojs_public.tar.gz"

if (Test-Path $cacheTar) {
    Write-Host "[INFO] Restore cache <- cache.tar.gz"
    docker compose cp "$cacheTar" "ojs_app:/tmp/ojs_cache.tar.gz" | Out-Null
    docker compose exec -T ojs_app sh -lc "mkdir -p /var/www/html/cache; find /var/www/html/cache -mindepth 1 -delete; tar xzf /tmp/ojs_cache.tar.gz -C /var/www/html/cache"
    docker compose exec -T ojs_app sh -lc "rm -f /tmp/ojs_cache.tar.gz"
}

if (Test-Path $filesTar) {
    $filesDir = docker compose exec -T ojs_app sh -lc "if [ -d /var/ojs-files ]; then echo /var/ojs-files; elif [ -d /var/www/html/files_data_journal ]; then echo /var/www/html/files_data_journal; else echo /var/ojs-files; fi"
    $filesDir = ($filesDir | Select-Object -First 1).Trim()

    Write-Host "[INFO] Restore files_dir ($filesDir) <- files.tar.gz"
    docker compose cp "$filesTar" "ojs_app:/tmp/ojs_files.tar.gz" | Out-Null
    docker compose exec -T ojs_app sh -lc "mkdir -p '$filesDir'; find '$filesDir' -mindepth 1 -delete; tar xzf /tmp/ojs_files.tar.gz -C '$filesDir'"
    docker compose exec -T ojs_app sh -lc "rm -f /tmp/ojs_files.tar.gz"
}

if (Test-Path $configFile) {
    Write-Host "[INFO] Restore config.inc.php (opsional)"
    docker compose cp "$configFile" "ojs_app:/var/www/html/config.inc.php" | Out-Null
    docker compose exec -T ojs_app sh -lc "chown www-data:www-data /var/www/html/config.inc.php"
}

Write-Host "[OK] Restore selesai. Disarankan restart service app: docker compose restart ojs_app"
