#requires -version 5.1
$ErrorActionPreference = 'Stop'
$setupLock = $null
$notificationScript = Join-Path $PSScriptRoot 'Send-SetupNotification.ps1'
try {
    try {
        $setupLock = [IO.File]::Open((Join-Path $PSScriptRoot 'setup.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        Write-Host '設定プログラムは既に起動しています。'
        exit 0
    }
    & $notificationScript -Message 'Printer maintenance Start.'
    $installScript = Join-Path $PSScriptRoot 'install.ps1'
    if (-not (Test-Path -LiteralPath $installScript)) {
        throw '同じフォルダーに install.ps1 が見つかりません。'
    }
    do {
        $inputDays = Read-Host '何日ごとに印刷しますか？ (既定: 7)'
        $intervalDays = 7
        $valid = [string]::IsNullOrWhiteSpace($inputDays) -or (
            [int]::TryParse($inputDays, [ref]$intervalDays) -and $intervalDays -ge 1
        )
        if (-not $valid) { Write-Host '1以上の整数を入力してください。' }
    } until ($valid)

    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -IntervalDays {1} -ScheduleTime 08:45' -f $installScript, $intervalDays
    $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -ne 0) { throw ('設定処理が終了コード {0} で終了しました。' -f $process.ExitCode) }
} catch {
    Write-Host $_.Exception.Message
    exit 1
} finally {
    if ($setupLock) {
        $setupLock.Dispose()
    }
}
