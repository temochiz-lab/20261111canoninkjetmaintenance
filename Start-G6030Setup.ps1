#requires -version 5.1
$ErrorActionPreference = 'Stop'
try {
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

    $arguments = '-NoProfile -NoExit -ExecutionPolicy Bypass -File "{0}" -IntervalDays {1} -ScheduleTime 08:45' -f $installScript, $intervalDays
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments -ErrorAction Stop
} catch {
    Write-Host $_.Exception.Message
    exit 1
}
