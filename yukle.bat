@echo off
setlocal
chcp 65001 >nul
title GitHub xaxa - Dosya Indirici
cd /d "%~dp0"
set "GITHUB_INDIR_BAT=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$all=[IO.File]::ReadAllText($env:GITHUB_INDIR_BAT,[Text.Encoding]::UTF8); $mark='# POWERSHELL_START'; $pos=$all.LastIndexOf($mark); if($pos -lt 0){throw 'Indirme kodu bulunamadi.'}; Invoke-Expression $all.Substring($pos+$mark.Length)"
set "sonuc=%errorlevel%"
echo.
if not "%sonuc%"=="0" echo Islem hata kodu: %sonuc%
echo Pencereyi kapatmak icin bir tusa basin.
pause >nul
exit /b %sonuc%
# POWERSHELL_START
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$api = 'https://api.github.com/repos/34kurulum/program/releases/tags/xaxa'
$target = Join-Path (Split-Path -Parent $env:GITHUB_INDIR_BAT) 'indirilenler'
$null = New-Item -ItemType Directory -Path $target -Force

function Show-Bar {
    param([long]$Current, [long]$Total, [double]$Elapsed)
    if ($Total -gt 0) {
        $ratio = [Math]::Min(1.0, [Math]::Max(0.0, $Current / [double]$Total))
    } else {
        $ratio = 0.0
    }
    $percent = [int][Math]::Floor($ratio * 100)
    $fill = [int][Math]::Floor($ratio * 28)
    $bar = ('#' * $fill) + ('-' * (28 - $fill))
    $speed = $Current / 1MB / [Math]::Max(0.1, $Elapsed)
    $line = ('  [{0}] {1,3}%  {2:0.0}/{3:0.0} MB  {4:0.0} MB/s' -f $bar, $percent, ($Current / 1MB), ($Total / 1MB), $speed)
    [Console]::Write("`r" + $line.PadRight([Math]::Max(72, $line.Length)))
}

function Download-Asset {
    param([string]$Url, [string]$Output, [long]$ExpectedSize)
    $part = $Output + '.part'
    if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }
    $client = $null
    $response = $null
    $source = $null
    $destination = $null
    $started = [Diagnostics.Stopwatch]::StartNew()
    $downloaded = [long]0
    $lastPaint = -1000.0
    $drawn = $false
    try {
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromMinutes(60)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('Github-Release-Downloader/1.0')
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $destination = [IO.File]::Open($part, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] 131072
        Show-Bar -Current 0 -Total $ExpectedSize -Elapsed 0
        $drawn = $true
        while (($count = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $destination.Write($buffer, 0, $count)
            $downloaded += $count
            if (($started.Elapsed.TotalMilliseconds - $lastPaint) -ge 120) {
                Show-Bar -Current $downloaded -Total $ExpectedSize -Elapsed $started.Elapsed.TotalSeconds
                $lastPaint = $started.Elapsed.TotalMilliseconds
            }
        }
        $destination.Flush()
        $destination.Dispose()
        $destination = $null
        if ($downloaded -ne $ExpectedSize) {
            throw ('Eksik indirme: {0} / {1} bayt' -f $downloaded, $ExpectedSize)
        }
        Show-Bar -Current $downloaded -Total $ExpectedSize -Elapsed $started.Elapsed.TotalSeconds
        [Console]::WriteLine()
        $drawn = $false
        Move-Item -LiteralPath $part -Destination $Output -Force
    } catch {
        if ($drawn) { [Console]::WriteLine() }
        throw
    } finally {
        if ($destination) { $destination.Dispose() }
        if ($source) { $source.Dispose() }
        if ($response) { $response.Dispose() }
        if ($client) { $client.Dispose() }
    }
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '               GITHUB  XAXA  INDIRICI' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '  Kaynak : 34kurulum/program  -  xaxa'
Write-Host ('  Klasor : ' + $target)
Write-Host ''

try {
    Write-Host '  GitHub dosya listesi aliniyor...' -ForegroundColor Yellow
    $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Github-Release-Downloader/1.0'; 'Accept' = 'application/vnd.github+json' }
    $assets = @($release.assets)
    if ($assets.Count -eq 0) { throw 'Bu surumde indirilecek dosya bulunamadi.' }
    Write-Host ('  Bulunan dosya: ' + $assets.Count) -ForegroundColor Green
    Write-Host ''
} catch {
    Write-Host ('  GITHUB HATASI: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

$downloadCount = 0
$skippedCount = 0
$failed = @()
$index = 0
foreach ($asset in $assets) {
    $index++
    $name = [string]$asset.name
    $destination = Join-Path $target $name
    $size = [long]$asset.size
    Write-Host ('  [{0}/{1}] {2}' -f $index, $assets.Count, $name) -ForegroundColor Cyan

    if ((Test-Path -LiteralPath $destination -PathType Leaf) -and ((Get-Item -LiteralPath $destination).Length -eq $size)) {
        Write-Host '    [OK] Zaten indirilmis, atlaniyor.' -ForegroundColor DarkGreen
        $skippedCount++
        Write-Host ''
        continue
    }

    $succeeded = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Download-Asset -Url ([string]$asset.browser_download_url) -Output $destination -ExpectedSize $size
            Write-Host '    [OK] Indirildi.' -ForegroundColor Green
            $downloadCount++
            $succeeded = $true
            break
        } catch {
            $reason = $_.Exception.Message
            Remove-Item -LiteralPath ($destination + '.part') -Force -ErrorAction SilentlyContinue
            if ($attempt -lt 3) {
                Write-Host ('    [!] Hata, tekrar deneniyor ({0}/3): {1}' -f $attempt, $reason) -ForegroundColor Yellow
            } else {
                Write-Host ('    [X] Indirilemedi: ' + $reason) -ForegroundColor Red
                $failed += ($name + ' - ' + $reason)
            }
        }
    }
    Write-Host ''
}

$logPath = Join-Path $target 'indirilemeyenler.txt'
if ($failed.Count -gt 0) {
    $failed | Set-Content -LiteralPath $logPath -Encoding UTF8
} else {
    Remove-Item -LiteralPath $logPath -ErrorAction SilentlyContinue
}

Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host '                       SONUC' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkCyan
Write-Host ('  Yeni indirilen : ' + $downloadCount) -ForegroundColor Green
Write-Host ('  Zaten bulunan : ' + $skippedCount)
Write-Host ('  Indirilemeyen  : ' + $failed.Count) -ForegroundColor $(if ($failed.Count -gt 0) {'Red'} else {'Green'})
Write-Host ('  Kayit klasoru  : ' + $target)
if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host '  Indirilemeyen dosyalar:' -ForegroundColor Red
    foreach ($item in $failed) { Write-Host ('  - ' + $item) -ForegroundColor Red }
    Write-Host ('  Hata listesi: ' + $logPath) -ForegroundColor Yellow
    exit 1
}
Write-Host ''
Write-Host '  Tum dosyalar kontrol edildi. Bitti!' -ForegroundColor Green
