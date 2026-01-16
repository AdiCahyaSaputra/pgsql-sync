param()

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  backup.ps1 -f <user:pass@host:port/db> -t <user:pass@host:port/db> [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -f, --from           Source DB connection string"
    Write-Host "  -t, --to             Destination DB connection string"
    Write-Host "  -o, --outdir         Output directory or full .sql file path"
    Write-Host "  -l, --log-file       Log file path (default: stdout)"
    Write-Host "  -c, --clean-restore  Drop destination DB first (asks for confirmation)"
    Write-Host "  -h, --help           Show this help"
}

function Parse-Conn {
    param([string]$Conn)
    if ($Conn -notmatch '^([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$') {
        throw "Invalid connection string: $Conn"
    }
    return @{
        User = $Matches[1]
        Pass = $Matches[2]
        Host = $Matches[3]
        Port = $Matches[4]
        Db   = $Matches[5]
    }
}

function Invoke-Checked {
    param(
        [string]$File,
        [string[]]$Args
    )
    & $File @Args
    if ($LASTEXITCODE -ne 0) {
        throw "$File failed with exit code $LASTEXITCODE"
    }
}

$fromConn = $null
$toConn = $null
$outParam = $null
$logFile = $null
$cleanRestore = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '-f' { $fromConn = $args[++$i] }
        '--from' { $fromConn = $args[++$i] }
        '-t' { $toConn = $args[++$i] }
        '--to' { $toConn = $args[++$i] }
        '-o' { $outParam = $args[++$i] }
        '--outdir' { $outParam = $args[++$i] }
        '-l' { $logFile = $args[++$i] }
        '--log-file' { $logFile = $args[++$i] }
        '-c' { $cleanRestore = $true }
        '--clean-restore' { $cleanRestore = $true }
        '-h' { Show-Usage; exit 0 }
        '--help' { Show-Usage; exit 0 }
        default { throw "Unknown argument: $($args[$i])" }
    }
}

if (-not $fromConn) { throw "--from is required" }
if (-not $toConn) { throw "--to is required" }

$from = Parse-Conn $fromConn
$to = Parse-Conn $toConn

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ($outParam) {
    if ($outParam -match '\.sql$') {
        $outFile = $outParam
        $outDir = Split-Path -Parent $outFile
    } else {
        $outDir = $outParam
        $outFile = Join-Path $outDir "dump-$($from.Db)-$timestamp.sql"
    }
} else {
    $outDir = Join-Path $HOME "backup-db"
    $outFile = Join-Path $outDir "dump-$($from.Db)-$timestamp.sql"
}

[void][System.IO.Directory]::CreateDirectory($outDir)

if ($logFile) {
    $logDir = Split-Path -Parent $logFile
    if ($logDir) { [void][System.IO.Directory]::CreateDirectory($logDir) }
    Start-Transcript -Path $logFile -Append | Out-Null
}

try {
    if ($cleanRestore) {
        $confirm = Read-Host "This will drop destination database '$($to.Db)'. Type 'y' to continue"
        if ($confirm -ne "y") {
            throw "Aborted by user"
        }
    }

    Write-Host "Dumping source database to $outFile"
    $env:PGPASSWORD = $from.Pass
    Invoke-Checked "pg_dump" @(
        "-h", $from.Host, "-p", $from.Port, "-U", $from.User,
        "--inserts", "--no-privileges", "--no-owner", "--clean", "--create", "--if-exists",
        "--file", $outFile, $from.Db
    )

    if ($cleanRestore) {
        Write-Host "Dropping destination database $($to.Db)"
        $env:PGPASSWORD = $to.Pass
        Invoke-Checked "psql" @(
            "-h", $to.Host, "-p", $to.Port, "-U", $to.User, "-d", "postgres", "-v", "ON_ERROR_STOP=1",
            "-c", "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$($to.Db)' AND pid <> pg_backend_pid();",
            "-c", "DROP DATABASE IF EXISTS `"$($to.Db)`";"
        )
    }

    Write-Host "Restoring dump into destination server"
    $env:PGPASSWORD = $to.Pass
    Invoke-Checked "psql" @(
        "-h", $to.Host, "-p", $to.Port, "-U", $to.User, "-d", "postgres", "-v", "ON_ERROR_STOP=1",
        "-f", $outFile
    )

    Write-Host "Done"
} finally {
    $env:PGPASSWORD = $null
    if ($logFile) {
        Stop-Transcript | Out-Null
    }
}
