#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Message)

$ErrorActionPreference = 'Stop'
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
    $payload = @{ topic=$settings['topicname']; title=$settings['pcname']; message=$Message } | ConvertTo-Json -Compress
    [void](Invoke-RestMethod -Uri 'https://ntfy.sh' -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 15)
    Write-Host ('ntfy: {0}' -f $Message)
} catch {
    Write-Warning ('ntfy notification failed: {0}' -f $_.Exception.Message)
}
