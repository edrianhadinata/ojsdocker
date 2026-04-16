$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

param(
    [string]$BackupRoot = "backup"
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

function Copy-FromContainerIfExists {
    param(
        [string]$Service,
        [string]$ContainerPath,
        [string]$HostPath
    )

    $exists = docker compose exec -T $Service sh -lc "test -f '$ContainerPath' && echo yes || echo no"
    if (($exists | Select-Object -First 1).Trim() -eq "yes") {
        docker compose cp "${Service}:${ContainerPath}" "$HostPath" | Out-Null
        return $true
    }

    return $false
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

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $BackupRoot $timestamp
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

Write-Host "[INFO] Backup database -> db.sql"
docker compose exec -T ojs_db sh -lc "mysqldump -u'$dbUser' -p'$dbPassword' '$dbName' --single-transaction --quick --lock-tables=false > /tmp/ojs_backup.sql"
docker compose cp "ojs_db:/tmp/ojs_backup.sql" (Join-Path $backupDir "db.sql") | Out-Null
docker compose exec -T ojs_db sh -lc "rm -f /tmp/ojs_backup.sql"

Write-Host "[INFO] Backup public files -> public.tar.gz"
docker compose exec -T ojs_app sh -lc "mkdir -p /tmp; tar czf /tmp/ojs_public.tar.gz -C /var/www/html/public ."
docker compose cp "ojs_app:/tmp/ojs_public.tar.gz" (Join-Path $backupDir "public.tar.gz") | Out-Null
docker compose exec -T ojs_app sh -lc "rm -f /tmp/ojs_public.tar.gz"

Write-Host "[INFO] Backup cache -> cache.tar.gz"
docker compose exec -T ojs_app sh -lc "mkdir -p /tmp; tar czf /tmp/ojs_cache.tar.gz -C /var/www/html/cache ."
docker compose cp "ojs_app:/tmp/ojs_cache.tar.gz" (Join-Path $backupDir "cache.tar.gz") | Out-Null
docker compose exec -T ojs_app sh -lc "rm -f /tmp/ojs_cache.tar.gz"

$filesDir = docker compose exec -T ojs_app sh -lc "if [ -d /var/ojs-files ]; then echo /var/ojs-files; elif [ -d /var/www/html/files_data_journal ]; then echo /var/www/html/files_data_journal; fi"
$filesDir = ($filesDir | Select-Object -First 1).Trim()
if (-not [string]::IsNullOrWhiteSpace($filesDir)) {
    Write-Host "[INFO] Backup files_dir ($filesDir) -> files.tar.gz"
    docker compose exec -T ojs_app sh -lc "mkdir -p /tmp; tar czf /tmp/ojs_files.tar.gz -C '$filesDir' ."
    docker compose cp "ojs_app:/tmp/ojs_files.tar.gz" (Join-Path $backupDir "files.tar.gz") | Out-Null
    docker compose exec -T ojs_app sh -lc "rm -f /tmp/ojs_files.tar.gz"
} else {
    Write-Host "[WARN] Direktori files_dir tidak ditemukan. Lewati backup files.tar.gz"
}

Write-Host "[INFO] Backup config.inc.php (opsional)"
$copiedConfig = Copy-FromContainerIfExists -Service "ojs_app" -ContainerPath "/var/www/html/config.inc.php" -HostPath (Join-Path $backupDir "config.inc.php")
if (-not $copiedConfig) {
    Write-Host "[WARN] config.inc.php belum ada di container."
}

$manifest = @(
    "timestamp=$timestamp"
    "database=$dbName"
    "db_user=$dbUser"
    "files_dir=$filesDir"
) -join "`n"
Set-Content -Path (Join-Path $backupDir "manifest.txt") -Value $manifest -Encoding ascii

Write-Host "[OK] Backup selesai di: $backupDir"
