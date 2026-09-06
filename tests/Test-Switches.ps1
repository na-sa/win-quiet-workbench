#requires -Version 5.1
param([switch]$ConfirmCase,[switch]$Decline)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '..\Set-ZenithStyle.ps1'
$text = [IO.File]::ReadAllText((Resolve-Path $source))
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
# Run the full script control flow, substituting only OS interactions in a
# temporary copy. Never apply these fake functions to the shipping script.
$replacements = @{
    'Read-Value' = @'
function Read-Value($Path,$Name) {
 $id = "$Path/$Name"
 if ($global:fakeValues.ContainsKey($id)) { return $global:fakeValues[$id] }
 [pscustomobject]@{Path=$Path;Name=$Name;Exists=$false;Kind=$null;Value=$null}
}
'@
    'Ensure-RegistryKey' = 'function Ensure-RegistryKey($Path) {}'
    'Get-ActiveScheme' = "function Get-ActiveScheme { '11111111-2222-3333-4444-555555555555' }"
    'Set-LidValue' = @'
function Set-LidValue($Path,$Name,$Value) {
 $global:fakeValues["$Path/$Name"] = [pscustomobject]@{Path=$Path;Name=$Name;Exists=$true;Kind='DWord';Value=$Value}
}
'@
    'New-VerifiedRestorePoint' = @'
function New-VerifiedRestorePoint {
 $global:restoreCalls++
 [pscustomobject]@{Description='Test restore point';SequenceNumber=42}
}
'@
}
$functions = $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)
foreach ($fn in ($functions | Sort-Object {$_.Extent.StartOffset} -Descending)) {
 if ($replacements.ContainsKey($fn.Name)) { $text = $text.Remove($fn.Extent.StartOffset,$fn.Extent.EndOffset-$fn.Extent.StartOffset).Insert($fn.Extent.StartOffset,$replacements[$fn.Name]) }
}
$text = $text -replace '(?m)^\$admin = .*$', '$admin = $true # Test-only elevation simulation'
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('QuietWorkbenchTests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testDir) | Out-Null
$testScript = Join-Path $testDir 'Subject.ps1'
[IO.File]::WriteAllText($testScript,$text)
function Get-CimInstance($ClassName) {
 if ($ClassName -eq 'Win32_StartupCommand') { [pscustomobject]@{Name='Example startup app'} }
 elseif ($ClassName -eq 'Win32_SystemEnclosure') { [pscustomobject]@{ChassisTypes=@(10)} }
 else { throw 'Unexpected CIM class' }
}
function New-ItemProperty {
 param($LiteralPath,$Name,$PropertyType,$Value,[switch]$Force)
 if ($LiteralPath -notmatch '^HK(CU|LM):') { throw 'Unexpected registry target' }
 $global:fakeValues["$LiteralPath/$Name"] = [pscustomobject]@{Path=$LiteralPath;Name=$Name;Exists=$true;Kind=[string]$PropertyType;Value=$Value}
}
function Remove-ItemProperty($LiteralPath,$Name) { $global:fakeValues.Remove("$LiteralPath/$Name") }
function Start-Process($FilePath) {
 if ($FilePath -ne 'ms-settings:search') { throw 'Unexpected process launch' }
 $global:settingsLaunches++
}
function Reset-TestState {
 $global:fakeValues = @{}
 foreach ($mode in @('AC','DC')) {
  $path = 'PowerPlan:11111111-2222-3333-4444-555555555555'
  $global:fakeValues["$path/$mode"] = [pscustomobject]@{Path=$path;Name=$mode;Exists=$true;Kind='DWord';Value=1}
 }
 $global:restoreCalls=0; $global:settingsLaunches=0
}
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Out-Host { param([Parameter(ValueFromPipeline=$true)]$InputObject) process {} }
function Invoke-Case($Options) { & $testScript @Options 6>$null 3>$null }
function Latest-Backup { (Get-ChildItem (Join-Path $testDir 'zenith-backups') | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName }
try {
 if ($ConfirmCase) {
  Reset-TestState
  & $testScript -Apply -UserSettingsOnly -Confirm
  if ($Decline) {
   Assert ($global:fakeValues.Count -eq 2 -and $global:restoreCalls -eq 0) 'Confirm No-to-All caused changes'
   Write-Output 'PASS: interactive Confirm No-to-All'
  } else {
   Assert ($global:fakeValues.Count -eq 9) 'Confirm Yes-to-All did not apply seven user settings'
   Write-Output 'PASS: interactive Confirm Yes-to-All'
  }
  return
 }
 foreach ($options in @(@{},@{PerformanceReport=$true},@{PerformanceOptions=$true},@{Apply=$true;WhatIf=$true;PerformanceOptions=$true},@{ReviewIndexing=$true;WhatIf=$true})) {
  Reset-TestState; Invoke-Case $options
  Assert ($global:fakeValues.Count -eq 2 -and $global:restoreCalls -eq 0 -and $global:settingsLaunches -eq 0) 'Read-only mode had side effects'
 }
 Write-Output 'PASS: default, report, performance preview, WhatIf, indexing WhatIf'
 Reset-TestState; Invoke-Case @{ReviewIndexing=$true}
 Assert ($global:settingsLaunches -eq 1 -and $global:fakeValues.Count -eq 2) 'Indexing review did not open exactly one settings page'
 Write-Output 'PASS: ReviewIndexing dispatch'
 foreach ($case in @(@{Options=@{Apply=$true};Count=10},@{Options=@{Apply=$true;SkipLidSettings=$true};Count=10},@{Options=@{Apply=$true;UserSettingsOnly=$true};Count=9},@{Options=@{Apply=$true;PerformanceOptions=$true;Confirm=$false};Count=15})) {
  Reset-TestState
  Invoke-Case $case.Options
  Assert ($global:fakeValues.Count -eq $case.Count) 'Wrong setting count'
  Assert ($global:restoreCalls -eq 1) 'Restore point must run once per apply'
  if ($case.Options.ContainsKey('SkipLidSettings') -or $case.Options.ContainsKey('UserSettingsOnly')) {
   Assert ($global:fakeValues['PowerPlan:11111111-2222-3333-4444-555555555555/AC'].Value -eq 1) 'Excluded lid setting changed'
  }
  $backup = Latest-Backup
  $log = Get-ChildItem (Join-Path $testDir 'zenith-logs') | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  $records = @(Get-Content $log.FullName | ForEach-Object { $_ | ConvertFrom-Json })
  $expectedChanges = if ($case.Options.ContainsKey('SkipLidSettings') -or $case.Options.ContainsKey('UserSettingsOnly')) { $case.Count - 2 } else { $case.Count }
  Assert (@($records | Where-Object { $_.Operation -eq 'Apply' -and $_.Status -eq 'Succeeded' }).Count -eq $expectedChanges) 'Missing apply success logs'
  $beforeCount = $global:fakeValues.Count
  Invoke-Case @{RestoreFrom=$backup;WhatIf=$true}
  Assert ($global:fakeValues.Count -eq $beforeCount) 'Restore WhatIf mutated settings'
  Invoke-Case @{RestoreFrom=$backup}
  Assert ($global:fakeValues.Count -eq 2) 'Restore failed to remove originally absent settings'
  Assert ($global:fakeValues['PowerPlan:11111111-2222-3333-4444-555555555555/AC'].Value -eq 1) 'Restore failed to restore lid action'
 }
 Write-Output 'PASS: Apply, SkipLidSettings, UserSettingsOnly, PerformanceOptions, Confirm false, RestoreFrom and restore WhatIf'
 Reset-TestState
 $p='HKCU:\Control Panel\Desktop\WindowMetrics'
 $global:fakeValues["$p/MinAnimate"]=[pscustomobject]@{Path=$p;Name='MinAnimate';Exists=$true;Kind='String';Value='1'}
 Invoke-Case @{Apply=$true;PerformanceOptions=$true}
 Assert ($global:fakeValues["$p/MinAnimate"].Kind -eq 'String' -and $global:fakeValues["$p/MinAnimate"].Value -eq '0') 'Animation string write failed'
 $backup=Latest-Backup
 Invoke-Case @{Apply=$true;PerformanceOptions=$true}
 Assert ($global:restoreCalls -eq 1) 'Idempotent rerun created another restore point'
 Invoke-Case @{RestoreFrom=$backup}
 Assert ($global:fakeValues["$p/MinAnimate"].Value -eq '1') 'String restore failed'
 Write-Output 'PASS: string type preservation and idempotent apply'
 $rejected=$false
 try { Invoke-Case @{Apply=$true;RestoreFrom=$backup} } catch { $rejected=$true }
 Assert $rejected 'Conflicting modes accepted'
 Write-Output 'PASS: conflicting modes rejected'
} finally {
 # Delete only the freshly generated filesystem test directory.
 $resolved=[IO.Path]::GetFullPath($testDir)
 $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or ([IO.Path]::GetFileName($resolved) -notmatch '^QuietWorkbenchTests-[0-9a-f]{32}$')) { throw 'Invalid cleanup path' }
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
