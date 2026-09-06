#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$source = Join-Path $PSScriptRoot '..\Set-ZenithStyle.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$definition = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Ensure-RegistryKey'}, $true)
if (-not $definition) { throw 'Ensure-RegistryKey was not found.' }
. ([scriptblock]::Create($definition.Extent.Text))

# Exercise a disposable registry key, never the user's Windows preferences.
$testPath = 'HKCU:\Software\QuietWorkbenchTest-' + [guid]::NewGuid().ToString('N')
try {
    Ensure-RegistryKey $testPath
    New-ItemProperty -LiteralPath $testPath -Name Sentinel -PropertyType String -Value 'Preserve me' | Out-Null
    New-ItemProperty -LiteralPath $testPath -Name Setting -PropertyType DWord -Value 1 | Out-Null
    Ensure-RegistryKey $testPath
    New-ItemProperty -LiteralPath $testPath -Name Setting -PropertyType DWord -Value 0 -Force | Out-Null
    if ((Get-ItemPropertyValue -LiteralPath $testPath -Name Sentinel) -ne 'Preserve me') { throw 'Existing data was altered.' }
    if ((Get-ItemPropertyValue -LiteralPath $testPath -Name Setting) -ne 0) { throw 'Value update failed.' }
    Write-Host 'PASS: missing key created, existing key preserved, value updated.'
} finally {
    if ($testPath -notmatch '^HKCU:\\Software\\QuietWorkbenchTest-[0-9a-f]{32}$') { throw 'Unexpected cleanup target.' }
    if (Test-Path -LiteralPath $testPath) { Remove-Item -LiteralPath $testPath }
}
