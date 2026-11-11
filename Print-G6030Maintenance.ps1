#requires -version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Notify
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
$script:ExitCode = 0
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$statePath = Join-Path $PSScriptRoot 'state.json'
$logDirectory = Join-Path $PSScriptRoot 'logs'
$logPath = Join-Path $logDirectory 'maintenance.log'
$lockPath = Join-Path $PSScriptRoot 'maintenance.lock'
$lockStream = $null
$config = $null

function Write-MaintenanceLog {
    param([ValidateSet('INFO','SKIP','WARN','ERROR')][string]$Level, [string]$Message)
    if (-not (Test-Path -LiteralPath $logDirectory)) { [void](New-Item -ItemType Directory -Path $logDirectory -Force) }
    $line = '{0} {1} {2}' -f $Level, (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, $utf8NoBom)
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value)
    $temp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 8), $utf8NoBom)
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Read-StateSafely {
    if (-not (Test-Path -LiteralPath $statePath)) { return [pscustomobject]@{} }
    try { return (Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch {
        $backup = '{0}.corrupt.{1}' -f $statePath, (Get-Date).ToString('yyyyMMddHHmmss')
        Move-Item -LiteralPath $statePath -Destination $backup
        Write-MaintenanceLog 'WARN' ('STATE_RESET backup="{0}"' -f [IO.Path]::GetFileName($backup))
        return [pscustomobject]@{}
    }
}

function Escape-LogValue([string]$Value) { return ($Value -replace '[\r\n"]', '_') }

function Send-MaintenanceNotification {
    param([string]$Message)
    if (-not $Notify -or $DryRun -or [bool]$config.dryRun) { return }
    try {
        $settings = @{}
        foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'setting.txt') -Encoding UTF8) {
            if ($line -match '^\s*(#|$)') { continue }
            if ($line -notmatch '^\s*(topicname|pcname)\s*=\s*(.*?)\s*$') { throw 'setting_invalid line' }
            $settings[$matches[1]] = $matches[2]
        }
        if (-not $settings['topicname'] -or $settings['topicname'] -eq 'your-ntfy-topic' -or
            $settings['topicname'] -notmatch '^[A-Za-z0-9_-]+$') { throw 'setting_invalid topicname' }
        if (-not $settings['pcname'] -or $settings['pcname'] -eq 'your-device-name') { throw 'setting_invalid pcname' }
        $payload = @{ topic = $settings['topicname']; title = $settings['pcname']; message = $Message } | ConvertTo-Json -Compress
        [void](Invoke-RestMethod -Uri 'https://ntfy.sh' -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 15)
        Write-MaintenanceLog 'INFO' ('NOTIFY result=sent message="{0}"' -f (Escape-LogValue $Message))
    } catch {
        Write-MaintenanceLog 'WARN' ('NOTIFY result=failed message="{0}"' -f (Escape-LogValue $_.Exception.Message))
    }
}

function Send-DayNotification {
    param([bool]$IsPrintDay)
    $message = if ($IsPrintDay) { 'Today is printer test day.' } else { 'Today is no print test.' }
    Send-MaintenanceNotification -Message $message
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "config_not_found path=$ConfigPath" }
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.printerName) { throw 'config_invalid printerName is required' }
    if ($config.paper -and $config.paper -ne 'A4') { throw 'config_invalid only A4 is supported' }

    try {
        $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        Write-MaintenanceLog 'SKIP' 'SKIP reason=already_running'
        exit 0
    }

    Send-MaintenanceNotification -Message 'Printer maintenance Start.'
    $printerName = [string]$config.printerName
    Write-MaintenanceLog 'INFO' ('START printer="{0}"' -f (Escape-LogValue $printerName))

    $state = Read-StateSafely
    $minimumDays = if ($null -ne $config.minimumIntervalDays) { [int]$config.minimumIntervalDays } else { 20 }
    if (-not $Force -and $state.PSObject.Properties.Name -contains 'lastSuccessfulSubmission') {
        $last = [DateTime]::Parse([string]$state.lastSuccessfulSubmission, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $skipForInterval = ((Get-Date).Date - $last.ToLocalTime().Date).Days -lt $minimumDays
        if ($skipForInterval) {
            Send-DayNotification -IsPrintDay $false
            Write-MaintenanceLog 'SKIP' ('SKIP reason=minimum_interval last={0}' -f $last.ToString('yyyy-MM-dd'))
            exit 0
        }
    }

    Send-DayNotification -IsPrintDay $true
    $printer = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($printerName -replace "'", "''")) -ErrorAction Stop
    if ($null -eq $printer) {
        Write-MaintenanceLog 'ERROR' 'ERROR reason=printer_not_found'
        exit 10
    }

    $spooler = Get-Service -Name Spooler -ErrorAction Stop
    if ($spooler.Status -ne 'Running') {
        Write-MaintenanceLog 'ERROR' ('ERROR reason=spooler_not_running status={0}' -f $spooler.Status)
        exit 11
    }

    $effectiveDryRun = $DryRun -or ([bool]$config.dryRun)
    if ($effectiveDryRun) {
        Write-MaintenanceLog 'INFO' 'DRY_RUN result=ready'
        Write-MaintenanceLog 'INFO' 'END result=dry_run'
        exit 0
    }

    Add-Type -AssemblyName System.Drawing
    $document = New-Object System.Drawing.Printing.PrintDocument
    $document.DocumentName = 'G6030 Periodic Maintenance'
    $document.PrinterSettings.PrinterName = $printerName
    if (-not $document.PrinterSettings.IsValid) { throw 'printer_settings_invalid' }
    $document.PrinterSettings.Copies = 1
    $document.DefaultPageSettings.Landscape = $false
    $a4 = $null
    foreach ($size in $document.PrinterSettings.PaperSizes) { if ($size.Kind -eq [Drawing.Printing.PaperKind]::A4) { $a4 = $size; break } }
    if ($null -eq $a4) { $a4 = New-Object Drawing.Printing.PaperSize('A4', 827, 1169) }
    $document.DefaultPageSettings.PaperSize = $a4

    $printedAt = Get-Date
    $machine = [Environment]::MachineName
    $handler = {
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
        $left = $e.MarginBounds.Left; $top = $e.MarginBounds.Top; $width = $e.MarginBounds.Width
        $font = New-Object Drawing.Font('Arial', 9)
        $titleFont = New-Object Drawing.Font('Arial', 13, [Drawing.FontStyle]::Bold)
        $black = [Drawing.Brushes]::Black
        $g.DrawString('G6030 Periodic Maintenance', $titleFont, $black, $left, $top)
        $info = '{0} / {1} / {2}' -f $printedAt.ToString('yyyy-MM-dd HH:mm:ss'), $machine, $printerName
        $g.DrawString($info, $font, $black, $left, $top + 27)

        $barY = $top + 72; $barH = 58; $gap = 14
        $colors = @([Drawing.Color]::Black, [Drawing.Color]::FromArgb(0,255,255), [Drawing.Color]::FromArgb(255,0,255), [Drawing.Color]::FromArgb(255,255,0))
        foreach ($color in $colors) {
            $brush = New-Object Drawing.SolidBrush($color)
            $g.FillRectangle($brush, $left, $barY, $width, $barH)
            $brush.Dispose(); $barY += $barH + $gap
        }

        $gradY = $barY + 8
        $rect = New-Object Drawing.Rectangle($left, $gradY, $width, 62)
        $gradient = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, [Drawing.Color]::FromArgb(0,255,255), [Drawing.Color]::FromArgb(255,0,255), 0.0)
        $blend = New-Object Drawing.Drawing2D.ColorBlend
        $blend.Colors = @([Drawing.Color]::FromArgb(0,255,255), [Drawing.Color]::FromArgb(255,0,255), [Drawing.Color]::FromArgb(255,255,0))
        $blend.Positions = @(0.0, 0.5, 1.0)
        $gradient.InterpolationColors = $blend
        $g.FillRectangle($gradient, $rect); $gradient.Dispose()

        $lineY = $gradY + 100
        foreach ($lineWidth in @(0.5, 1.0, 2.0)) {
            $pen = New-Object Drawing.Pen([Drawing.Color]::Black, $lineWidth)
            $g.DrawLine($pen, $left, $lineY, $left + $width, $lineY)
            $pen.Dispose(); $lineY += 30
        }
        $thinPen = New-Object Drawing.Pen([Drawing.Color]::Black, 0.5)
        for ($x = $left; $x -le ($left + $width); $x += 25) { $g.DrawLine($thinPen, $x, $lineY, $x, $lineY + 75) }
        for ($y = $lineY; $y -le ($lineY + 75); $y += 25) { $g.DrawLine($thinPen, $left, $y, $left + $width, $y) }
        $thinPen.Dispose()
        $g.DrawString('BLACK  CYAN  MAGENTA  YELLOW  |  0.5pt  1pt  2pt', $font, $black, $left, $lineY + 92)
        $font.Dispose(); $titleFont.Dispose()
        $e.HasMorePages = $false
    }
    $document.add_PrintPage($handler)
    try { $document.Print() } finally { $document.remove_PrintPage($handler); $document.Dispose() }

    $newState = [ordered]@{ lastSuccessfulSubmission = $printedAt.ToUniversalTime().ToString('o'); result = 'success'; printerName = $printerName; document = 'G6030 Periodic Maintenance' }
    Write-JsonAtomic -Path $statePath -Value $newState
    Write-MaintenanceLog 'INFO' 'SUBMITTED document="G6030 Periodic Maintenance"'
    Write-MaintenanceLog 'INFO' 'END result=success'
} catch {
    try { Write-MaintenanceLog 'ERROR' ('ERROR reason=exception type={0} message="{1}"' -f $_.Exception.GetType().Name, (Escape-LogValue $_.Exception.Message)) } catch {}
    $script:ExitCode = 1
} finally {
    if ($lockStream) {
        try { Send-MaintenanceNotification -Message 'Printer maintenance Exit.' }
        finally { $lockStream.Dispose() }
    }
    try {
        if (Test-Path -LiteralPath $logPath) {
            $retention = if ($config -and $null -ne $config.logRetentionDays) { [int]$config.logRetentionDays } else { 365 }
            if ((Get-Item -LiteralPath $logPath).LastWriteTime -lt (Get-Date).AddDays(-$retention)) {
                Move-Item -LiteralPath $logPath -Destination ($logPath + '.' + (Get-Date).ToString('yyyyMMdd')) -Force
            }
        }
    } catch {}
}
exit $script:ExitCode
