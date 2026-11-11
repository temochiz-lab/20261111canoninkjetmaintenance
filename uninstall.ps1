#requires -version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$RemoveFiles)

$ErrorActionPreference = 'Stop'
$taskName = 'G6030 Periodic Maintenance Print'
& schtasks.exe /Delete /TN $taskName /F 2>$null
if ($LASTEXITCODE -ne 0) { Write-Verbose 'タスクは存在しないか、既に削除されています。' }
if ($RemoveFiles) {
    $installDir = 'C:\ProgramData\G6030Maintenance'
    if ($PSCmdlet.ShouldProcess($installDir, 'プログラム、設定、ログを削除')) { Remove-Item -LiteralPath $installDir -Recurse -Force }
}
Write-Host 'タスクを削除しました。プリンタードライバーには変更を加えていません。'
