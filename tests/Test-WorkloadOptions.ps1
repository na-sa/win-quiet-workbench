#requires -Version 5.1
$ErrorActionPreference='Stop'
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
$repo=Split-Path $PSScriptRoot -Parent
$text=[IO.File]::ReadAllText((Join-Path $repo 'Set-WorkloadOptions.ps1'))
foreach ($part in @('Common','Workloads')) {
    $text=$text.Replace(". (Join-Path `$PSScriptRoot 'lib\$part.ps1')",[IO.File]::ReadAllText((Join-Path $repo "lib\$part.ps1")))
}
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
Assert (-not $errors.Count) 'Parse failed'
$replace=@{
    'Read-WorkloadRegistry'=@'
function Read-WorkloadRegistry($Path,$Name) {
 if ($global:values.ContainsKey("$Path/$Name")) { return $global:values["$Path/$Name"] }
 [pscustomobject]@{Path=$Path;Name=$Name;Exists=$false;Kind=$null;Value=$null}
}
'@
    'Set-WorkloadRegistry'=@'
function Set-WorkloadRegistry($Path,$Name,$Kind,$Value) {
 $global:values["$Path/$Name"]=[pscustomobject]@{Path=$Path;Name=$Name;Exists=$true;Kind=$Kind;Value=$Value}
}
'@
    'Test-DevDriveRequest'='function Test-DevDriveRequest($Path,$Letter,$SizeGB) {}'
    'Ensure-WorkbenchDevDrive'='function Ensure-WorkbenchDevDrive($Path,$Letter,$SizeGB) { $global:resourceCalls++ }'
    'Ensure-WslWorkspace'='function Ensure-WslWorkspace($Distro) { $global:resourceCalls++ }'
    'Test-OllamaGpu'='function Test-OllamaGpu($Model) { $global:resourceCalls++ }'
    'Show-ChromeExtensionReport'='function Show-ChromeExtensionReport { $global:reports++ }'
    'New-VerifiedRestorePoint'=@'
function New-VerifiedRestorePoint {
 $global:restoreCalls++
 if ($global:failRestore) { throw 'Test restore failure' }
 [pscustomobject]@{Description='Test restore point';SequenceNumber=42}
}
'@
}
foreach ($fn in ($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true) | Sort-Object {$_.Extent.StartOffset} -Descending)) {
    if ($replace.ContainsKey($fn.Name)) { $text=$text.Remove($fn.Extent.StartOffset,$fn.Extent.EndOffset-$fn.Extent.StartOffset).Insert($fn.Extent.StartOffset,$replace[$fn.Name]) }
}
$text=$text -replace '(?m)^\$admin=.*$', '$admin=$true # Test-only elevation'
$tempRoot=[IO.Path]::GetTempPath()
$testDir=Join-Path $tempRoot ('QuietWorkloadTests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testDir) | Out-Null
$subject=Join-Path $testDir 'Subject.ps1'
[IO.File]::WriteAllText($subject,$text)
function Remove-ItemProperty($LiteralPath,$Name) { $global:values.Remove("$LiteralPath/$Name") }
function Get-Item($LiteralPath,$ErrorAction) {
    if ($LiteralPath -ne 'HKCU:\Software\Policies\Google\Chrome\TabDiscardingExceptions') { throw 'Unexpected registry read' }
    $entries=@($global:values.Values | Where-Object Path -eq $LiteralPath)
    if (-not $entries.Count) { return $null }
    $key=[pscustomobject]@{Entries=$entries}
    $key | Add-Member ScriptMethod GetValueNames { @($this.Entries | ForEach-Object Name) }
    $key | Add-Member ScriptMethod GetValue { param($n) ($this.Entries | Where-Object Name -eq $n).Value }
    $key
}
function Read-Host { 'NO' }
function Reset-State { $global:values=@{}; $global:resourceCalls=0; $global:restoreCalls=0; $global:reports=0; $global:failRestore=$false }
function Run-Case($Options) { & $subject @Options 6>$null 3>$null }
$all=@{CreateDevDrive=$true;PrepareWslWorkspace=$true;CheckOllamaGpu=$true;DisableGameRecording=$true;ChromeMemorySaver=$true;ReviewChromeExtensions=$true}
try {
    foreach ($selection in @(@{CreateDevDrive=$true},@{PrepareWslWorkspace=$true},@{CheckOllamaGpu=$true},@{DisableGameRecording=$true},@{ChromeMemorySaver=$true},@{ReviewChromeExtensions=$true},$all)) {
        Reset-State
        Run-Case $selection
        Run-Case ($selection+@{Apply=$true;WhatIf=$true})
        Assert ($global:values.Count -eq 0 -and $global:resourceCalls -eq 0 -and $global:restoreCalls -eq 0) 'Preview/WhatIf mutated OS'
        Run-Case ($selection+@{Apply=$true})
        $expected=0; $resources=0
        if ($selection.DisableGameRecording) { $expected+=3 }
        if ($selection.ChromeMemorySaver) { $expected+=4 }
        foreach ($name in @('CreateDevDrive','PrepareWslWorkspace','CheckOllamaGpu')) { if ($selection[$name]) { $resources++ } }
        Assert ($global:values.Count -eq $expected -and $global:resourceCalls -eq $resources) 'Wrong changes'
        if ($expected+$resources -eq 0) { continue }
        Assert ($global:restoreCalls -eq 1) 'Restore point not attempted exactly once'
        $backup=(Get-ChildItem (Join-Path $testDir 'zenith-backups') | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName
        $log=(Get-ChildItem (Join-Path $testDir 'zenith-logs') | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName
        $success=@(Get-Content $log | ConvertFrom-Json | Where-Object {$_.Operation -eq 'Apply' -and $_.Status -eq 'Succeeded'})
        Assert ($success.Count -eq $expected+$resources) 'Missing verified change logs'
        Run-Case @{RestoreFrom=$backup;WhatIf=$true}
        Assert ($global:values.Count -eq $expected) 'Restore WhatIf mutated registry'
        Run-Case @{RestoreFrom=$backup}
        Assert ($global:values.Count -eq 0 -and $global:resourceCalls -eq $resources) 'Restore failed or deleted resources'
    }
    Reset-State
    Run-Case @{Apply=$true;DisableGameRecording=$true;ChromeMemorySaver=$true}
    Run-Case @{Apply=$true;DisableGameRecording=$true;ChromeMemorySaver=$true}
    Assert ($global:restoreCalls -eq 1) 'Repeated registry apply was not idempotent'
    Reset-State
    $path='HKCU:\Software\Policies\Google\Chrome\TabDiscardingExceptions'
    $global:values["$path/1"]=[pscustomobject]@{Path=$path;Name='1';Exists=$true;Kind='String';Value='existing.example'}
    Run-Case @{Apply=$true;ChromeMemorySaver=$true}
    Assert ($global:values["$path/1"].Value -eq 'existing.example' -and $global:values["$path/2"].Value -eq 'localhost' -and $global:values["$path/3"].Value -eq '127.0.0.1') 'Existing exception overwritten'
    $backup=(Get-ChildItem (Join-Path $testDir 'zenith-backups') | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName
    Run-Case @{RestoreFrom=$backup}
    Assert ($global:values.Count -eq 1 -and $global:values["$path/1"].Value -eq 'existing.example') 'Existing exception not preserved by restore'
    Reset-State; $global:failRestore=$true
    $rejected=$false
    try { Run-Case ($all+@{Apply=$true}) } catch { $rejected=$true }
    Assert ($rejected -and $global:values.Count -eq 0 -and $global:resourceCalls -eq 0) 'Restore-point refusal did not stop mutations'
    Write-Output 'PASS: all workload switches, preview/WhatIf, apply, restore, log counts, registry idempotency, resource preservation, restore-point refusal'
} finally {
    $resolved=[IO.Path]::GetFullPath($testDir)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath($tempRoot),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^QuietWorkloadTests-[0-9a-f]{32}$') { throw 'Unsafe cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

. (Join-Path $repo 'lib\Workloads.ps1')
$disk=[pscustomobject]@{Number=9;IsBoot=$false;IsSystem=$false;PartitionStyle='RAW'}
$vhd=[pscustomobject]@{Attached=$true;DiskNumber=9}
Assert-WorkbenchDisk $vhd $disk
foreach ($bad in @(@{IsBoot=$true},@{IsSystem=$true},@{PartitionStyle='GPT'},@{Number=0})) {
    $candidate=[pscustomobject]@{Number=9;IsBoot=$false;IsSystem=$false;PartitionStyle='RAW'}
    foreach ($key in $bad.Keys) { $candidate.$key=$bad[$key] }
    $rejected=$false
    try { Assert-WorkbenchDisk $vhd $candidate } catch { $rejected=$true }
    Assert $rejected 'Unsafe disk accepted for formatting'
}
Assert (-not (Test-WorkloadRegistryEntry ([pscustomobject]@{Path='HKCU:\Software\Malicious';Name='1';Exists=$false}))) 'Unrelated restore path accepted'
Assert (-not (Test-WorkloadRegistryEntry ([pscustomobject]@{Path='HKCU:\Software\Policies\Google\Chrome';Name='ExtensionInstallBlocklist';Exists=$false}))) 'Unmanaged policy accepted'
function Invoke-WorkbenchWsl($Distro,$Command) {
    Assert ($Command.Contains('test ! -L') -and $Command.Contains('stat -f') -and $Command.Contains('mkdir -p')) 'WSL filesystem safeguards missing'
    '/home/test/projects'
}
Ensure-WslWorkspace 'Ubuntu'
$script:gpuBytes=1GB; $script:generateCalls=0
function Invoke-RestMethod($Uri,$TimeoutSec,$Method,$ContentType,$Body) {
    if ($Uri.EndsWith('/api/tags')) { return @{models=@(@{name='test:small';size=2GB})} }
    if ($Uri.EndsWith('/api/generate')) { $script:generateCalls++; return @{done=$true} }
    if ($Uri.EndsWith('/api/ps')) {
        if ($script:generateCalls -eq 0) { return @{models=@()} }
        return @{models=@([pscustomobject]@{name='test:small';size=2GB;size_vram=$script:gpuBytes})}
    }
    throw 'Unexpected endpoint'
}
Test-OllamaGpu ''
Assert ($script:generateCalls -eq 1) 'GPU check did not perform generation'
$script:gpuBytes=0; $rejected=$false
try { Test-OllamaGpu 'test:small' } catch { $rejected=$true }
Assert $rejected 'CPU fallback reported as GPU success'
$rejected=$false
try { Test-OllamaGpu 'missing:model' } catch { $rejected=$true }
Assert $rejected 'Missing model was accepted'
Write-Output 'PASS: disk-format guards, restore allowlist, WSL command guards, GPU inference/allocation checks, CPU fallback and missing-model detection'
