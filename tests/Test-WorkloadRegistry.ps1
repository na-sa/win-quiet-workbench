#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\lib\Workloads.ps1')
$path='HKCU:\Software\QuietWorkbenchTest-'+[guid]::NewGuid().ToString('N')
try {
    Set-WorkloadRegistry "$path\Missing\Nested" 'TestValue' 'DWord' 1
    if ((Read-WorkloadRegistry "$path\Missing\Nested" 'TestValue').Value -ne 1) { throw 'Nested key creation failed.' }
    Set-WorkloadRegistry "$path\Missing\Nested" 'Sentinel' 'String' 'preserve'
    Set-WorkloadRegistry "$path\Missing\Nested" 'TestValue' 'DWord' 0
    if ((Read-WorkloadRegistry "$path\Missing\Nested" 'Sentinel').Value -ne 'preserve') { throw 'Existing key contents were lost.' }
    Write-Output 'PASS: real disposable nested HKCU creation and existing-value preservation'
} finally {
    if ($path -notmatch '^HKCU:\\Software\\QuietWorkbenchTest-[0-9a-f]{32}$') { throw 'Unsafe registry cleanup path.' }
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
}
