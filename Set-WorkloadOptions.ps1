#requires -Version 5.1
<#
.SYNOPSIS
Prepare development storage, check Ollama GPU use, and configure capture and Chrome preferences.
.DESCRIPTION
Preview by default. -Apply creates backups and verified change logs.
Storage preparation is additive. Existing projects are never moved or deleted.
Registry rollback retains development volumes and their files.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [string]$RestoreFrom,
    [switch]$CreateDevDrive,
    [switch]$PrepareWslWorkspace,
    [switch]$CheckOllamaGpu,
    [switch]$DisableGameRecording,
    [switch]$ChromeMemorySaver,
    [switch]$ReviewChromeExtensions,
    [string]$DevDrivePath = (Join-Path $env:LOCALAPPDATA 'QuietWorkbench\DevDrive.vhdx'),
    [ValidatePattern('^[D-Z]$')][string]$DevDriveLetter = 'V',
    [ValidateRange(50,1024)][int]$DevDriveSizeGB = 100,
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]*$')][string]$WslDistro = 'Ubuntu',
    [string]$OllamaModel,
    [string[]]$ChromeKeepAliveSites = @('localhost','127.0.0.1')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-bit Windows PowerShell or PowerShell is required.' }
if ($Apply -and $RestoreFrom) { throw 'Choose apply or restore.' }
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:quietWorkbenchRoot=$PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Workloads.ps1')
Write-Warning 'USE AT YOUR OWN RISK. Review the preview and keep backups. Dev Drive creation uses a new virtual disk only. Restore keeps development files and volumes. GPU testing briefly uses compute resources. Chrome Memory Saver can reload inactive tabs.'

$chromePath='HKCU:\Software\Policies\Google\Chrome'
$exceptionPath="$chromePath\TabDiscardingExceptions"
$registrySettings=@()
if ($DisableGameRecording) {
    $registrySettings+=@(
        @{Path='HKCU:\System\GameConfigStore';Name='GameDVR_Enabled';Value=0;Kind='DWord';Label='Disable Game DVR';Description='Disables Windows game recording for this user; game clips will not be captured by Game DVR.'},
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR';Name='AppCaptureEnabled';Value=0;Kind='DWord';Label='Disable game app capture';Description='Turns off the user game-capture preference. Snipping Tool is unaffected.'},
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR';Name='HistoricalCaptureEnabled';Value=0;Kind='DWord';Label='Disable background game recording';Description='Turns off background capture for retrospective game clips.'}
    )
}
if ($ChromeMemorySaver) {
    $registrySettings+=@(
        @{Path=$chromePath;Name='HighEfficiencyModeEnabled';Value=1;Kind='DWord';Label='Enable Chrome Memory Saver';Description='Allows Chrome to reclaim inactive-tab memory. Tabs may reload when revisited; Chrome may show that settings are managed.'},
        @{Path=$chromePath;Name='MemorySaverModeSavings';Value=0;Kind='DWord';Label='Use moderate Chrome memory savings';Description='Uses the moderate Memory Saver level to limit tab-discard aggressiveness.'}
    )
    # Add exceptions in free numeric slots, retaining existing policy entries.
    $existing=Get-Item -LiteralPath $exceptionPath -ErrorAction SilentlyContinue
    $names=@(); $values=@()
    if ($existing) { $names=@($existing.GetValueNames()); $values=@($names | ForEach-Object { $existing.GetValue($_) }) }
    foreach ($site in ($ChromeKeepAliveSites | Select-Object -Unique)) {
        if ($site -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]*$') { throw 'ChromeKeepAliveSites accepts host names or IPv4 addresses, without paths or wildcards.' }
        if ($values -contains $site) { continue }
        $slot=1
        while ($names -contains [string]$slot) { $slot++ }
        $names += [string]$slot
        $registrySettings+=@{Path=$exceptionPath;Name=[string]$slot;Value=$site;Kind='String';Label="Keep Chrome tabs for $site active";Description="Exempts $site from tab discarding. Add other monitoring hostnames with -ChromeKeepAliveSites."}
    }
}

if ($RestoreFrom) {
    $backup=Import-Clixml -LiteralPath $RestoreFrom
    if ($backup.Schema -ne 'QuietWorkbenchWorkloads-v1' -or $backup.Computer -ne $env:COMPUTERNAME -or $backup.UserSid -ne $identity.User.Value) { throw 'Wrong backup schema, computer, or user.' }
    foreach ($entry in $backup.Entries) {
        if (-not (Test-WorkloadRegistryEntry $entry)) { throw 'Backup contains an unsupported registry entry.' }
    }
    foreach ($entry in $backup.Entries) {
        if ($PSCmdlet.ShouldProcess("$($entry.Path) / $($entry.Name)",'Restore previous workload preference')) {
            $before=Read-WorkloadRegistry $entry.Path $entry.Name
            Invoke-LoggedChange 'Restore' "Restore previous workload preference: $($entry.Name)" $before $entry $RestoreFrom {
                if ($entry.Exists) { Set-WorkloadRegistry $entry.Path $entry.Name $entry.Kind $entry.Value }
                elseif ((Read-WorkloadRegistry $entry.Path $entry.Name).Exists) { Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name }
                $actual=Read-WorkloadRegistry $entry.Path $entry.Name
                if ($actual.Exists -ne $entry.Exists -or ($entry.Exists -and ($actual.Kind -ne $entry.Kind -or $actual.Value -ne $entry.Value))) { throw 'Workload restore verification failed.' }
            }
        }
    }
    Write-Host 'Registry restore processed. Development volumes, folders, and files are retained; see README for detaching a Dev Drive.'
    return
}

$pending=@()
foreach ($setting in $registrySettings) {
    $old=Read-WorkloadRegistry $setting.Path $setting.Name
    $changed=-not $old.Exists -or $old.Kind -ne $setting.Kind -or $old.Value -ne $setting.Value
    Write-Host ("{0}: current={1}; target={2}; change={3}" -f $setting.Label,$old.Value,$setting.Value,$changed)
    if ($changed) { $pending+=@{Setting=$setting;Old=$old} }
}
if ($CreateDevDrive) { Test-DevDriveRequest $DevDrivePath $DevDriveLetter $DevDriveSizeGB; Write-Host "Dev Drive: prepare $DevDrivePath, maximum $DevDriveSizeGB GB, drive ${DevDriveLetter}: with Projects and Packages folders. No automatic startup mount task is created." }
if ($PrepareWslWorkspace) { Write-Host "WSL: prepare ~/projects inside $WslDistro. Existing repositories remain where they are." }
if ($CheckOllamaGpu) { Write-Host 'Ollama: run one short local generation using an installed model, then verify its reported GPU memory allocation. No model download or server restart.' }
if ($ReviewChromeExtensions) { Show-ChromeExtensionReport }
if (-not $Apply) { Write-Host 'Preview only. Add -Apply to execute the selected options.'; return }
if ($CreateDevDrive -and -not $admin -and -not $WhatIfPreference) { throw 'Creating or mounting a Dev Drive requires an administrator PowerShell under this same account.' }

$backupPath=$null
$script:workloadRestoreHandled=$false
function Initialize-WorkloadBackup {
    if (-not $script:workloadBackupPath) {
        $backupDir=Join-Path $PSScriptRoot 'zenith-backups'
        [IO.Directory]::CreateDirectory($backupDir) | Out-Null
        $script:workloadBackupPath=Join-Path $backupDir ('workloads-' + [guid]::NewGuid().ToString('N') + '.clixml')
        [pscustomobject]@{Schema='QuietWorkbenchWorkloads-v1';Computer=$env:COMPUTERNAME;UserSid=$identity.User.Value;Created=Get-Date;Entries=@($pending | ForEach-Object {$_.Old});DevDrivePath=$DevDrivePath;WslDistro=$WslDistro;ResourcesRetainedOnRestore=$true} | Export-Clixml -LiteralPath $script:workloadBackupPath
        Write-Host "Backup: $script:workloadBackupPath"
    }
    if (-not $script:workloadRestoreHandled) { Confirm-RestorePointOrContinue $script:workloadBackupPath; $script:workloadRestoreHandled=$true }
}
$script:workloadBackupPath=$null
foreach ($item in $pending) {
    $setting=$item.Setting
    if ($PSCmdlet.ShouldProcess("$($setting.Path) / $($setting.Name)",$setting.Label)) {
        Initialize-WorkloadBackup
        $before=Read-WorkloadRegistry $setting.Path $setting.Name
        $target=[pscustomobject]@{Exists=$true;Kind=$setting.Kind;Value=$setting.Value}
        Invoke-LoggedChange 'Apply' $setting.Description $before $target $script:workloadBackupPath {
            Set-WorkloadRegistry $setting.Path $setting.Name $setting.Kind $setting.Value
            $actual=Read-WorkloadRegistry $setting.Path $setting.Name
            if (-not $actual.Exists -or $actual.Kind -ne $setting.Kind -or $actual.Value -ne $setting.Value) { throw 'Registry verification failed.' }
        }
    }
}
foreach ($resource in @('DevDrive','WslWorkspace','OllamaGpu')) {
    $selected=($resource -eq 'DevDrive' -and $CreateDevDrive) -or ($resource -eq 'WslWorkspace' -and $PrepareWslWorkspace) -or ($resource -eq 'OllamaGpu' -and $CheckOllamaGpu)
    if (-not $selected -or -not $PSCmdlet.ShouldProcess($resource,'Prepare or verify workload resource')) { continue }
    Initialize-WorkloadBackup
    $before=[pscustomobject]@{Path="Workload:$resource";Name=$resource;Exists=$null;Kind='Resource';Value='Prior state not captured here; Dev Drive ownership and provisioning state are recorded in its adjacent manifest.'}
    $target=[pscustomobject]@{Exists=$true;Kind='Resource';Value='Verified'}
    $description=switch ($resource) {
        'DevDrive' { "Prepare Windows development folders on ${DevDriveLetter}: in $DevDrivePath. Existing disks and projects are preserved." }
        'WslWorkspace' { "Prepare ~/projects in the $WslDistro Linux filesystem for future Linux builds." }
        'OllamaGpu' { 'Verify an installed Ollama model uses GPU memory during a short local inference.' }
    }
    Invoke-LoggedChange 'Apply' $description $before $target $script:workloadBackupPath {
        switch ($resource) {
            'DevDrive' { Ensure-WorkbenchDevDrive $DevDrivePath $DevDriveLetter $DevDriveSizeGB }
            'WslWorkspace' { Ensure-WslWorkspace $WslDistro }
            'OllamaGpu' { Test-OllamaGpu $OllamaModel }
        }
    }
}
Write-Host 'Selected workload operations finished. Chrome policy may need a policy reload or browser restart. No automatic restart was performed.'
