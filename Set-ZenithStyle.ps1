#requires -Version 5.1
<#
.SYNOPSIS
Preview or apply a small Zenith-inspired Windows 11 settings baseline.
.DESCRIPTION
No arguments previews only. -Apply backs up changed values before writing.
Each attempted change is logged before writing and after verification.
Before applying, attempts a verified Windows restore point; on failure asks
whether to continue without one. Only an explicit yes continues.
Run as the same Windows user; use an elevated PowerShell for long paths.
This does not install Project Zenith or applications. No automatic restart.
.EXAMPLE
.\Set-ZenithStyle.ps1
.EXAMPLE
.\Set-ZenithStyle.ps1 -Apply
.EXAMPLE
.\Set-ZenithStyle.ps1 -RestoreFrom .\zenith-backups\backup-EXAMPLE.clixml
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [string]$RestoreFrom,
    [switch]$UserSettingsOnly,
    [switch]$SkipLidSettings
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Write-Warning 'USE AT YOUR OWN RISK. This script changes Windows preferences and laptop power behavior. Review the preview and keep the backup. A laptop running with its lid closed can drain its battery or overheat in a bag; sleep or shut it down before packing it away.'
if ($Apply -and $RestoreFrom) { throw 'Choose -Apply or -RestoreFrom, not both.' }
if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
if (-not [Environment]::Is64BitProcess) { throw 'Run this in 64-bit PowerShell.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$settings = @(
    @{Path="$explorer\Advanced"; Name='HideFileExt'; Value=0; Label='Show file extensions'},
    @{Path="$explorer\Advanced"; Name='Hidden'; Value=1; Label='Show hidden files'},
    @{Path="$explorer\CabinetState"; Name='FullPath'; Value=1; Label='Show full path in Explorer title'},
    @{Path=$explorer; Name='ShowRecent'; Value=0; Label='Hide recent files in Explorer Home'},
    @{Path=$explorer; Name='ShowFrequent'; Value=0; Label='Hide frequent folders in Explorer Home'},
    @{Path="$explorer\Advanced"; Name='ShowSyncProviderNotifications'; Value=0; Label='Disable Explorer sync-provider tips'},
    @{Path="$explorer\Advanced"; Name='Start_IrisRecommendations'; Value=0; Label='Disable Start tips and app recommendations'},
    @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name='LongPathsEnabled'; Value=1; Label='Enable long paths for compatible applications'}
)
$explanations = @{
    HideFileExt='Shows suffixes such as .txt and .ps1 so you can identify file types.'
    Hidden='Shows normally hidden files and folders; protected operating-system files stay hidden.'
    FullPath='Displays the complete folder path in the File Explorer title bar.'
    ShowRecent='Hides the recent-files list in Explorer Home without deleting your files.'
    ShowFrequent='Hides frequently used folders in Explorer Home without deleting folders.'
    ShowSyncProviderNotifications='Stops sync-provider tips and promotional messages inside Explorer.'
    Start_IrisRecommendations='Turns off Start recommendations for tips, shortcuts, and new apps.'
    LongPathsEnabled='Allows compatible applications to use file paths beyond the legacy 260-character limit.'
    AC='Closing the lid does nothing while plugged in, so closing it alone will not put the laptop to sleep.'
    DC='Closing the lid does nothing on battery, so closing it alone will not put the laptop to sleep; battery use continues.'
}
function Invoke-PowerCfg([string[]]$Arguments) {
    $output = & "$env:SystemRoot\System32\powercfg.exe" @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg failed ($LASTEXITCODE): $output" }
    $output -join "`n"
}
function Get-ActiveScheme {
    $result = Invoke-PowerCfg @('/getactivescheme')
    $match = [regex]::Match($result, '(?i)[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}')
    if (-not $match.Success) { throw 'Could not identify the active power scheme.' }
    $match.Value
}
function Test-PowerEntry($Entry) {
    $Entry.Path -match '^PowerPlan:[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -and $Entry.Name -in @('AC','DC')
}
if (-not $RestoreFrom -and -not $SkipLidSettings -and -not $UserSettingsOnly) {
    $chassis = @(Get-CimInstance Win32_SystemEnclosure | ForEach-Object { $_.ChassisTypes })
    if (@($chassis | Where-Object { $_ -in @(8,9,10,14,31,32) }).Count) {
        $scheme = Get-ActiveScheme
        Write-Host "Laptop detected. Lid-close changes target power plan $scheme (plugged in and battery)."
        $settings += @{Path="PowerPlan:$scheme"; Name='AC'; Value=0; Label='Lid close: do nothing when plugged in'}
        $settings += @{Path="PowerPlan:$scheme"; Name='DC'; Value=0; Label='Lid close: do nothing on battery'}
    } else { Write-Host 'Laptop chassis not detected; lid-close settings skipped.' }
}
if ($UserSettingsOnly) { $settings = @($settings | Where-Object { $_.Path -like 'HKCU:*' }) }

function Read-Value($Path, $Name) {
    if ($Path -like 'PowerPlan:*') {
        if (-not (Test-PowerEntry ([pscustomobject]@{Path=$Path; Name=$Name}))) { throw 'Invalid power setting.' }
        $schemeId = $Path.Substring(10)
        $output = Invoke-PowerCfg @('/qh', $schemeId, 'SUB_BUTTONS', 'LIDACTION')
        # The final two hexadecimal indexes are AC then DC, independent of UI language.
        $indexes = [regex]::Matches($output, '0x([0-9a-fA-F]{8})')
        if ($indexes.Count -ne 2) { throw 'Cannot reliably read both lid-close indexes; no guessed values will be used.' }
        $index = if ($Name -eq 'AC') { 0 } else { 1 }
        $value = [Convert]::ToInt32($indexes[$index].Groups[1].Value,16)
        if ($value -notin @(0,1,2,3)) { throw 'Unexpected lid-close action index.' }
        return [pscustomobject]@{Path=$Path; Name=$Name; Exists=$true; Value=$value; Kind='DWord'}
    }
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    $exists = $null -ne $key -and $key.GetValueNames() -contains $Name
    $value = $null
    $kind = $null
    if ($exists) {
        $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $key.GetValueKind($Name).ToString()
    }
    [pscustomobject]@{Path=$Path; Name=$Name; Exists=$exists; Value=$value; Kind=$kind}
}

function Set-LidValue($Path, $Name, $Value) {
    $schemeId = $Path.Substring(10)
    $option = if ($Name -eq 'AC') { '/setacvalueindex' } else { '/setdcvalueindex' }
    Invoke-PowerCfg @($option, $schemeId, 'SUB_BUTTONS', 'LIDACTION', [string]$Value) | Out-Null
    # Refresh only if this is still the active plan. Restore does not switch plans.
    if ((Get-ActiveScheme) -eq $schemeId) { Invoke-PowerCfg @('/setactive', $schemeId) | Out-Null }
}

$script:changeLogPath = $null
function Write-ChangeLog {
    param($Operation, $Status, $Description, $Before, $Target, $BackupFile, $Detail)
    if (-not $script:changeLogPath) {
        $logDir = Join-Path $PSScriptRoot 'zenith-logs'
        [System.IO.Directory]::CreateDirectory($logDir) | Out-Null
        $script:changeLogPath = Join-Path $logDir ("changes-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
        Write-Host "Change log: $script:changeLogPath"
    }
    $record = [ordered]@{
        Timestamp = [DateTimeOffset]::Now.ToString('o')
        Operation = $Operation
        Status = $Status
        Description = $Description
        SettingPath = $Before.Path
        ValueName = $Before.Name
        Before = [ordered]@{Exists=$Before.Exists; Type=$Before.Kind; Value=$Before.Value}
        Target = [ordered]@{Exists=$Target.Exists; Type=$Target.Kind; Value=$Target.Value}
        BackupFile = $BackupFile
        Detail = $Detail
    }
    $line = $record | ConvertTo-Json -Depth 8 -Compress
    # Synchronous append: if logging fails before the write, do not change Windows.
    [System.IO.File]::AppendAllText($script:changeLogPath, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    if ($Status -eq 'Succeeded' -and $Operation -in @('Apply','Restore')) {
        $verb = if ($Operation -eq 'Restore') { 'restored' } else { 'applied' }
        Write-Host "Setting $verb - here's what it does: $Description"
    } else { Write-Host "[$Status] $Description" }
}

function Invoke-LoggedChange {
    param($Operation, $Description, $Before, $Target, $BackupFile, [scriptblock]$Action)
    Write-ChangeLog $Operation 'Started' $Description $Before $Target $BackupFile 'About to modify the setting.'
    try {
        & $Action
        Write-ChangeLog $Operation 'Succeeded' $Description $Before $Target $BackupFile 'Setting value verified; Explorer and Start changes may require signing out and back in.'
    } catch {
        $changeError = $_
        try {
            Write-ChangeLog $Operation 'Failed' $Description $Before $Target $BackupFile $changeError.Exception.Message
        } catch {
            Write-Warning "Could not append the failure to the change log: $($_.Exception.Message)"
        }
        throw $changeError
    }
}

function New-VerifiedRestorePoint {
    # System Restore cmdlets are Windows PowerShell 5.1 commands. Use that
    # bundled runtime even when the main script is launched from PowerShell 7.
    $worker = {
        $ErrorActionPreference = 'Stop'
        try {
            Get-Command Checkpoint-Computer, Get-ComputerRestorePoint -ErrorAction Stop | Out-Null
            $description = 'Before Zenith-style settings ' + [guid]::NewGuid().ToString('N')
            $restoreWarnings = @()
            Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -WarningVariable restoreWarnings -WarningAction SilentlyContinue -ErrorAction Stop
            # The command can warn and skip creation due to Windows throttling.
            # A unique matching point, not just exit code zero, proves creation.
            $point = @(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.Description -eq $description })
            if (-not $point.Count) {
                throw ('No new restore point could be verified. System Protection may be disabled, or Windows may have limited creation because a recent restore point exists. ' + ($restoreWarnings -join ' '))
            }
            [pscustomobject]@{Success=$true; Description=$description; SequenceNumber=$point[-1].SequenceNumber; Error=$null} | ConvertTo-Json -Compress
        } catch {
            [pscustomobject]@{Success=$false; Description=$null; SequenceNumber=$null; Error=$_.Exception.Message} | ConvertTo-Json -Compress
        }
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker.ToString()))
    $runtime = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $output = & $runtime -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded
    if ($LASTEXITCODE -ne 0) { throw "Windows restore-point helper failed with exit code $LASTEXITCODE." }
    $result = ($output -join "`n") | ConvertFrom-Json
    if (-not $result.Success) { throw $result.Error }
    $result
}

function Confirm-RestorePointOrContinue($BackupFile) {
    $before = [pscustomobject]@{Path='Windows:SystemRestore'; Name='RestorePoint'; Exists=$false; Kind='RestorePoint'; Value=$null}
    $target = [pscustomobject]@{Exists=$true; Kind='RestorePoint'; Value='New restore point before settings changes'}
    Write-ChangeLog 'SystemRestore' 'Started' 'Create a Windows restore point before applying settings.' $before $target $BackupFile 'Attempting System Restore without changing its configuration.'
    $failure = $null
    $point = $null
    try {
        if (-not $admin) { throw 'Creating a Windows restore point requires an elevated PowerShell.' }
        $point = New-VerifiedRestorePoint
    } catch { $failure = $_.Exception.Message }
    if ($null -eq $failure) {
        $target.Value = $point.SequenceNumber
        Write-ChangeLog 'SystemRestore' 'Succeeded' "Windows restore point created: $($point.Description)" $before $target $BackupFile "Verified sequence number $($point.SequenceNumber)."
        return
    }
    Write-ChangeLog 'SystemRestore' 'Failed' 'A new Windows restore point was not created or could not be verified.' $before $target $BackupFile $failure
    Write-Warning "Restore point unavailable: $failure"
    try { $answer = Read-Host 'Continue applying settings WITHOUT a new Windows restore point? Type YES to proceed; anything else cancels' }
    catch { $answer = '' }
    if ($answer -and $answer.Trim() -ieq 'YES') {
        Write-ChangeLog 'SystemRestore' 'UserApproved' 'User chose to continue without a verified new Windows restore point.' $before $target $BackupFile 'Per-setting backup remains available.'
        return
    }
    Write-ChangeLog 'SystemRestore' 'Cancelled' 'Stopped before applying any settings.' $before $target $BackupFile 'No explicit YES response was received.'
    throw 'Cancelled. No settings were applied. The settings backup and attempt log were retained.'
}

if ($RestoreFrom) {
    $backup = Import-Clixml -LiteralPath $RestoreFrom
    if ($backup.Schema -ne 'ZenithStyle-v1' -or $backup.UserSid -ne $identity.User.Value -or $backup.Computer -ne $env:COMPUTERNAME) {
        throw 'Backup must belong to this computer and Windows user.'
    }
    # Only restore values managed by this script; validate the whole file first.
    foreach ($entry in $backup.Entries) {
        if (Test-PowerEntry $entry) {
            if ($UserSettingsOnly) { throw 'This backup includes power settings; omit -UserSettingsOnly when restoring it.' }
            if (-not $entry.Exists -or $entry.Kind -ne 'DWord' -or $entry.Value -notin @(0,1,2,3)) { throw 'Invalid lid-close backup value.' }
            if (-not $admin -and -not $WhatIfPreference) { throw 'Restore needs an elevated PowerShell.' }
            Read-Value $entry.Path $entry.Name | Out-Null
            continue
        }
        if (-not @($settings | Where-Object { $_.Path -eq $entry.Path -and $_.Name -eq $entry.Name }).Count) {
            throw "Backup contains an unsupported setting: $($entry.Path) / $($entry.Name)"
        }
        if ($entry.Path -like 'HKLM:*' -and -not $admin -and -not $WhatIfPreference) { throw 'Restore needs an elevated PowerShell.' }
    }
    foreach ($entry in $backup.Entries) {
        if ($PSCmdlet.ShouldProcess("$($entry.Path) / $($entry.Name)", 'Restore previous setting value')) {
            $before = Read-Value $entry.Path $entry.Name
            if (Test-PowerEntry $entry) {
                $actionName = @('Do nothing','Sleep','Hibernate','Shut down')[[int]$entry.Value]
                $description = "Restore lid-close action ($($entry.Name)) to '$actionName' in the backed-up power plan."
                Invoke-LoggedChange 'Restore' $description $before $entry (Resolve-Path -LiteralPath $RestoreFrom).Path {
                    Set-LidValue $entry.Path $entry.Name $entry.Value
                    if ((Read-Value $entry.Path $entry.Name).Value -ne $entry.Value) { throw 'Lid-close restore verification failed.' }
                }
                continue
            }
            $label = ($settings | Where-Object { $_.Path -eq $entry.Path -and $_.Name -eq $entry.Name }).Label
            $description = "Restore the previous setting for: $label"
            if (-not $entry.Exists) { $description += ' (remove the added registry value and return to the Windows default)' }
            Invoke-LoggedChange 'Restore' $description $before $entry (Resolve-Path -LiteralPath $RestoreFrom).Path {
            if ($entry.Exists) {
                New-Item -Path $entry.Path -Force | Out-Null
                New-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -PropertyType $entry.Kind -Value $entry.Value -Force | Out-Null
            } elseif ((Read-Value $entry.Path $entry.Name).Exists) {
                Remove-ItemProperty -LiteralPath $entry.Path -Name $entry.Name
            }
            $actual = Read-Value $entry.Path $entry.Name
            if ($actual.Exists -ne $entry.Exists -or ($entry.Exists -and ($actual.Kind -ne $entry.Kind -or (Compare-Object @($actual.Value) @($entry.Value))))) {
                throw "Restore verification failed: $($entry.Name)"
            }
            }
        }
    }
    if ($WhatIfPreference) { Write-Host 'Restore preview only. No settings changed.' }
    else { Write-Host 'Restore finished. Sign out and back in to refresh the Windows shell.' }
    return
}

$pending = @()
$report = foreach ($setting in $settings) {
    $old = Read-Value $setting.Path $setting.Name
    $changed = -not $old.Exists -or $old.Kind -ne 'DWord' -or $old.Value -ne $setting.Value
    if ($changed) { $pending += [pscustomobject]@{Setting=$setting; Old=$old} }
    [pscustomobject]@{
        Setting=$setting.Label
        Current=$(if ($old.Exists) { $old.Value } else { '(Windows default)' })
        Target=$setting.Value
        Change=$changed
    }
}
$report | Format-Table -AutoSize | Out-Host
if (-not $Apply) { Write-Host 'Preview only. Use -Apply to save a backup and apply these settings.'; return }
if (-not $pending.Count) { Write-Host 'All selected settings already match.'; return }
if (@($pending | Where-Object { $_.Setting.Path -like 'HKLM:*' -or $_.Setting.Path -like 'PowerPlan:*' }).Count -and -not $admin -and -not $WhatIfPreference) {
    throw 'Use an elevated PowerShell under this same account, or use -Apply -UserSettingsOnly. Nothing changed.'
}
$backupPath = $null
$restorePointHandled = $false
try {
    foreach ($item in $pending) {
        $setting = $item.Setting
        if ($PSCmdlet.ShouldProcess("$($setting.Path) / $($setting.Name)", "$($setting.Label): set DWORD to $($setting.Value)")) {
            if (-not $backupPath) {
                $backupDir = Join-Path $PSScriptRoot 'zenith-backups'
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                $backupPath = Join-Path $backupDir ("backup-{0}-{1}.clixml" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
                [pscustomobject]@{Schema='ZenithStyle-v1'; Computer=$env:COMPUTERNAME; UserSid=$identity.User.Value; Created=Get-Date; Entries=@($pending | ForEach-Object { $_.Old })} | Export-Clixml -LiteralPath $backupPath
                Write-Host "Backup: $backupPath"
            }
            if (-not $restorePointHandled) {
                Confirm-RestorePointOrContinue $backupPath
                $restorePointHandled = $true
            }
            $before = Read-Value $setting.Path $setting.Name
            $target = [pscustomobject]@{Exists=$true; Kind='DWord'; Value=$setting.Value}
            $description = "$($setting.Label). $($explanations[$setting.Name])"
            Invoke-LoggedChange 'Apply' $description $before $target $backupPath {
            if (Test-PowerEntry $setting) {
                Set-LidValue $setting.Path $setting.Name $setting.Value
            } else {
            New-Item -Path $setting.Path -Force | Out-Null
            New-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -PropertyType DWord -Value $setting.Value -Force | Out-Null
            }
            $actual = Read-Value $setting.Path $setting.Name
            if (-not $actual.Exists -or $actual.Kind -ne 'DWord' -or $actual.Value -ne $setting.Value) { throw "Verification failed: $($setting.Name)" }
            }
        }
    }
} catch {
    if ($backupPath -and $restorePointHandled) { Write-Warning "Some changes may have been applied. Restore using -RestoreFrom '$backupPath'." }
    throw
}
if ($backupPath) {
    Write-Host 'Selected settings applied and values verified. Sign out and back in to refresh the shell.'
    Write-Host 'Long-path support may need a reboot and only affects applications that support it.'
}
