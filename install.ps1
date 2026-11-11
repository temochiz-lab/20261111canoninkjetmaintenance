#requires -version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$PrinterName,
    [ValidateRange(1, 2147483647)][int]$IntervalDays = 1,
    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')][string]$ScheduleTime = '08:45',
    [switch]$WakeComputer,
    [switch]$RunOnlyWhenLoggedOn,
    [switch]$RunWhenLoggedOut,
    [switch]$SkipTaskRegistration
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$installDir = 'C:\ProgramData\G6030Maintenance'
$taskName = 'G6030 Periodic Maintenance Print'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'setting.txt'))) {
    throw 'setting.txt.sample を setting.txt にコピーし、topicname と pcname を設定してください。'
}

$candidates = @(Get-CimInstance Win32_Printer | Where-Object { $_.Name -match '(?i)(Canon|G6030|G6000)' } | Sort-Object Name)
if (-not $PrinterName) {
    if ($candidates.Count -eq 0) { throw 'Canon/G6030/G6000 を含むプリンターキューが見つかりません。-PrinterName で明示してください。' }
    Write-Host '対象プリンターを選択してください:'
    for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host ('[{0}] {1}' -f ($i + 1), $candidates[$i].Name) }
    do { $selection = Read-Host ('番号 (1-{0})' -f $candidates.Count) } until (($selection -as [int]) -ge 1 -and ($selection -as [int]) -le $candidates.Count)
    $PrinterName = $candidates[[int]$selection - 1].Name
}
if (-not (Get-CimInstance Win32_Printer | Where-Object Name -eq $PrinterName)) { throw "指定プリンターが存在しません: $PrinterName" }

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installDir 'logs') -Force | Out-Null
foreach ($file in @('install.ps1','Print-G6030Maintenance.ps1','uninstall.ps1','config.json.sample','setting.txt','Send-SetupNotification.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $installDir $file) -Force
}
$taskUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $installDir /grant:r ("{0}:(OI)(CI)M" -f $taskUser) /T /C | Out-Null
if ($LASTEXITCODE -ne 0) { throw "実行ユーザーのフォルダー権限設定に失敗しました (icacls exit $LASTEXITCODE)" }
$configPath = Join-Path $installDir 'config.json'
$config = [ordered]@{ printerName=$PrinterName; schedule=[ordered]@{type='daily';time=$ScheduleTime}; minimumIntervalDays=$IntervalDays; wakeComputer=[bool]$WakeComputer; logRetentionDays=365; paper='A4'; dryRun=$false }
[IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5), $utf8NoBom)

if (-not $SkipTaskRegistration) {
    $user = $taskUser
    $password = $null
    if ($RunWhenLoggedOut) {
        $credential = Get-Credential -UserName $user -Message 'ログアウト中にタスクを実行するWindowsアカウントのパスワードを入力してください（PINではありません）'
        $user = $credential.UserName
        $password = $credential.GetNetworkCredential().Password
        $logonType = 'Password'
    } else {
        $logonType = 'InteractiveToken'
    }
    $timeParts = $ScheduleTime.Split(':')
    $startBoundary = (Get-Date -Hour ([int]$timeParts[0]) -Minute ([int]$timeParts[1]) -Second 0).ToString('s')
    $wake = ([bool]$WakeComputer).ToString().ToLowerInvariant()
    $escapedUser = [Security.SecurityElement]::Escape($user)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Canon G6030 periodic one-page maintenance print.</Description></RegistrationInfo>
  <Triggers><CalendarTrigger><StartBoundary>$startBoundary</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$escapedUser</UserId><LogonType>$logonType</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><StartWhenAvailable>true</StartWhenAvailable><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><WakeToRun>$wake</WakeToRun><ExecutionTimeLimit>PT10M</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author"><Exec><Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command><Arguments>-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\ProgramData\G6030Maintenance\Print-G6030Maintenance.ps1" -Notify</Arguments><WorkingDirectory>C:\ProgramData\G6030Maintenance</WorkingDirectory></Exec></Actions>
</Task>
"@
    $taskXml = Join-Path $env:TEMP 'G6030MaintenanceTask.xml'
    try {
        [IO.File]::WriteAllText($taskXml, $xml, [Text.Encoding]::Unicode)
        if ($RunWhenLoggedOut) {
            & schtasks.exe /Create /TN $taskName /XML $taskXml /RU $user /RP $password /F | Out-Host
        } else {
            # Use the XML principal and explicitly select interactive logon.
            # Passing /RU without /RP can cause an unnecessary password prompt.
            & schtasks.exe /Create /TN $taskName /XML $taskXml /IT /F | Out-Host
        }
        if ($LASTEXITCODE -ne 0) { throw "タスク登録に失敗しました (schtasks exit $LASTEXITCODE)" }
        & (Join-Path $PSScriptRoot 'Send-SetupNotification.ps1') -Message 'Task registered successfully.'
    } finally { Remove-Item -LiteralPath $taskXml -Force -ErrorAction SilentlyContinue; $password = $null }
}

Write-Host "インストール完了: $installDir"
$choice = Read-Host '確認を選択: [P] 設定して1枚印刷 / [N] 設定のみで完了 (既定 N) / [D] 印刷せず動作確認'
if ($choice -match '^(?i)d$') { & (Join-Path $installDir 'Print-G6030Maintenance.ps1') -DryRun -Force }
elseif ($choice -match '^(?i)p$') { & (Join-Path $installDir 'Print-G6030Maintenance.ps1') -Force }
