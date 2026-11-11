#requires -version 5.1
[CmdletBinding()]
param(
    [int]$IntervalDays = 7,
    [string]$ScheduleTime = '08:45',
    [switch]$RunWhenLoggedOut
)

$ErrorActionPreference = 'Stop'
$errorPath = Join-Path $PSScriptRoot 'setup-error.log'
try {
    $parameters = @{ IntervalDays=$IntervalDays; ScheduleTime=$ScheduleTime; RunWhenLoggedOut=[bool]$RunWhenLoggedOut }
    & (Join-Path $PSScriptRoot 'install.ps1') @parameters
} catch {
    # Record the exception and source position only; never record credentials or a transcript.
    $detail = '{0}{1}{2}{1}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), [Environment]::NewLine, $_.Exception.Message, $_.InvocationInfo.PositionMessage
    try { [IO.File]::WriteAllText($errorPath, $detail, (New-Object Text.UTF8Encoding($true))) } catch {}
    Write-Host ''
    Write-Host '設定に失敗しました。以下のエラーを確認してください。' -ForegroundColor Red
    Write-Host $detail
    Write-Host ('エラー記録: {0}' -f $errorPath)
    try { [void](Read-Host 'Enterキーで閉じます') } catch {}
    exit 1
}
