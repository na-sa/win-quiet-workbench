#requires -Version 5.1
$ErrorActionPreference='Stop'
$script:quietWorkbenchRoot=Join-Path ([IO.Path]::GetTempPath()) ('QuietLogTest-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
try {
    $state=[pscustomobject]@{Path='Test';Name='Test';Exists=$false;Kind='Test';Value=$null}
    Write-ChangeLog 'Test' 'Started' 'Shared logging path test' $state $state '' ''
    if (-not $script:changeLogPath.StartsWith($script:quietWorkbenchRoot+'\zenith-logs\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Log was written outside the configured script root.' }
    Write-Output 'PASS: dot-sourced shared logging uses the caller output root'
} finally {
    $resolved=[IO.Path]::GetFullPath($script:quietWorkbenchRoot)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^QuietLogTest-[0-9a-f]{32}$') { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
