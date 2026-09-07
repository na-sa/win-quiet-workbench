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
    [switch]$SkipLidSettings,
    [switch]$PerformanceOptions,
    [switch]$PerformanceReport,
    [switch]$ReviewIndexing,
    [switch]$ServerOptions,
    [switch]$EnableDeveloperMode,
    [switch]$EnableStorageSense,
    [switch]$ReviewNotifications,
    [switch]$WorkloadOptions
)
if ($WorkloadOptions) {
    if ($RestoreFrom -or $UserSettingsOnly -or $SkipLidSettings -or $PerformanceOptions -or $PerformanceReport -or $ReviewIndexing -or $ServerOptions -or $EnableDeveloperMode -or $EnableStorageSense -or $ReviewNotifications) {
        throw 'Use -WorkloadOptions by itself, optionally with -Apply, -WhatIf, or -Confirm. Use Set-WorkloadOptions.ps1 for individual workload switches and restore.'
    }
    $forward = @{Apply=$Apply;CreateDevDrive=$true;PrepareWslWorkspace=$true;CheckOllamaGpu=$true;DisableGameRecording=$true;ChromeMemorySaver=$true;ReviewChromeExtensions=$true}
    foreach ($common in @('WhatIf','Confirm')) { if ($PSBoundParameters.ContainsKey($common)) { $forward[$common]=$PSBoundParameters[$common] } }
    & (Join-Path $PSScriptRoot 'Set-WorkloadOptions.ps1') @forward
    return
}
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
$performanceSettings = @(
    @{Path='HKCU:\Control Panel\Desktop\WindowMetrics'; Name='MinAnimate'; Value='0'; Kind='String'; Label='Reduce minimize and maximize animations'},
    @{Path="$explorer\Advanced"; Name='TaskbarAnimations'; Value=0; Label='Disable taskbar animations'},
    @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Value=0; Label='Disable transparency effects'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name='AllowNewsAndInterests'; Value=0; Label='Disable Widgets for this device'},
    @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name='IsDynamicSearchBoxEnabled'; Value=0; Label='Disable Search highlights'}
)
# Restore must recognize optional settings even when the preset is not supplied.
if ($PerformanceOptions -or $RestoreFrom) { $settings += $performanceSettings }
if ($ServerOptions -or $RestoreFrom) {
    $settings += @{Path="$explorer\Advanced\TaskbarDeveloperSettings"; Name='TaskbarEndTask'; Value=1; Label='Enable taskbar End task'}
}
if ($EnableDeveloperMode -or $RestoreFrom) {
    $settings += @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; Name='AllowDevelopmentWithoutDevLicense'; Value=1; Label='Enable Developer Mode'}
}
if ($EnableStorageSense -or $RestoreFrom) {
    $storagePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense'
    # Protect personal content before enabling automatic temporary-file cleanup.
    $settings += @(
        @{Path=$storagePath; Name='ConfigStorageSenseRecycleBinCleanupThreshold'; Value=0; Label='Preserve Recycle Bin contents'},
        @{Path=$storagePath; Name='ConfigStorageSenseDownloadsCleanupThreshold'; Value=0; Label='Preserve Downloads'},
        @{Path=$storagePath; Name='ConfigStorageSenseCloudContentDehydrationThreshold'; Value=0; Label='Keep cloud files locally available'},
        @{Path=$storagePath; Name='AllowStorageSenseTemporaryFilesCleanup'; Value=1; Label='Allow unused temporary-file cleanup'},
        @{Path=$storagePath; Name='AllowStorageSenseGlobal'; Value=1; Label='Enable conservative Storage Sense'}
    )
}
# Retain compatibility with backups from the former taskbar-button setting.
if ($RestoreFrom) { $settings += @{Path="$explorer\Advanced"; Name='TaskbarDa'; Value=0; Label='Widgets taskbar button (legacy)'} }
$explanations = @{
    TaskbarEndTask='Adds End task to supported taskbar app menus; using it can discard unsaved work. No app is terminated by this script.'
    AllowDevelopmentWithoutDevLicense='Enables Windows development features. Remote device discovery and Device Portal are not enabled by this script.'
    ConfigStorageSenseRecycleBinCleanupThreshold='Prevents Storage Sense from automatically emptying the Recycle Bin.'
    ConfigStorageSenseDownloadsCleanupThreshold='Prevents Storage Sense from automatically deleting Downloads.'
    ConfigStorageSenseCloudContentDehydrationThreshold='Prevents Storage Sense from automatically making cloud-backed files online-only.'
    AllowStorageSenseTemporaryFilesCleanup='Allows Windows to clean temporary files it considers unused. Restoring settings cannot recover deleted files.'
    AllowStorageSenseGlobal='Enables Storage Sense with the existing cleanup schedule. No cleanup is started by this script; supported Windows editions are required.'
    AC_SLEEP='Disables idle sleep while plugged in for this power plan. Hibernation, battery timers, manual sleep, and other power plans are unchanged.'
    AC_DISPLAY='Turns the display off after 10 idle minutes while plugged in; services can continue running.'
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
    MinAnimate='Reduces minimize and maximize window animations after signing out and back in; does not disable every app animation.'
    TaskbarAnimations='Disables taskbar animations after a shell refresh; visual responsiveness may improve.'
    EnableTransparency='Makes supported Windows surfaces opaque; performance gains may be small.'
    TaskbarDa='Hides the Widgets button to reduce distractions; does not uninstall Widgets or guarantee background processes stop.'
    AllowNewsAndInterests='Disables Widgets for all users through the Windows device policy; requires administrator rights and may require signing out or restarting. The app package is not uninstalled.'
    IsDynamicSearchBoxEnabled='Turns off Search highlights and featured content; local search remains available and web results are not globally disabled.'
}
if ($PerformanceReport -or $PerformanceOptions) {
    Write-Host 'Performance review: startup configuration is report-only and is never modified.'
    Write-Host 'Startup registrations can affect login time and background resource use. An entry does not prove it is enabled or currently running.'
    try {
        Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object -ExpandProperty Name -Unique | Sort-Object | ForEach-Object { Write-Host "  Startup item to review: $_" }
    } catch { Write-Warning "Could not list startup registrations: $($_.Exception.Message)" }
    Write-Host 'Use Task Manager > Startup apps to review measured startup impact. Review launchers, optional companions, local AI/container tools, and sync clients according to your needs.'
    Write-Host 'Keep security, VPN, management, and driver tools unless you know they are unnecessary. No performance improvement has been benchmarked by this script.'
    Write-Host 'Indexing review: exclude generated build output, dependency folders, or large datasets you do not search. Keep documents and email searchable.'
}
if ($ReviewIndexing) {
    Write-Host 'Indexing is a guided option: open Settings > Privacy & security > Search (or Searching Windows). Review Classic versus Enhanced and add specific excluded folders.'
    Write-Host 'Excluding folders reduces indexed coverage and can reduce indexing work; searches there may be slower or omit results. Windows Search will remain enabled.'
    if ($PSCmdlet.ShouldProcess('Windows Search settings', 'Open indexing settings for manual review')) {
        Start-Process 'ms-settings:search'
    }
}
if ($ReviewNotifications) {
    Write-Host 'Review Notifications > Do not disturb and automatic rules. Choose your focus hours and priority notifications; no schedule is assumed or changed by this script.'
    if ($PSCmdlet.ShouldProcess('Windows notification settings', 'Open notifications for manual review')) {
        Start-Process 'ms-settings:notifications'
    }
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
    $Entry.Path -match '^PowerPlan:[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -and $Entry.Name -in @('AC','DC','AC_SLEEP','AC_DISPLAY')
}
function Get-PowerTarget($Name) {
    switch ($Name) {
        'AC' { @('SUB_BUTTONS','LIDACTION',0) }
        'DC' { @('SUB_BUTTONS','LIDACTION',1) }
        'AC_SLEEP' { @('SUB_SLEEP','STANDBYIDLE',0) }
        'AC_DISPLAY' { @('SUB_VIDEO','VIDEOIDLE',0) }
        default { throw 'Invalid power setting name.' }
    }
}
function Test-PowerValue($Name, $Value) {
    if ($Name -in @('AC','DC')) { return $Value -in @(0,1,2,3) }
    return ($Value -is [int] -or $Value -is [uint32] -or $Value -is [long]) -and $Value -ge 0 -and $Value -le [uint32]::MaxValue
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
if ($ServerOptions -and -not $RestoreFrom -and -not $UserSettingsOnly) {
    $scheme = Get-ActiveScheme
    $settings += @{Path="PowerPlan:$scheme"; Name='AC_SLEEP'; Value=0; Label='Plugged-in idle sleep: Never'}
    $settings += @{Path="PowerPlan:$scheme"; Name='AC_DISPLAY'; Value=600; Label='Plugged-in display timeout: 10 minutes'}
}
if ($UserSettingsOnly) { $settings = @($settings | Where-Object { $_.Path -like 'HKCU:*' }) }
foreach ($setting in $settings) { if (-not $setting.ContainsKey('Kind')) { $setting.Kind = 'DWord' } }

function Read-Value($Path, $Name) {
    if ($Path -like 'PowerPlan:*') {
        if (-not (Test-PowerEntry ([pscustomobject]@{Path=$Path; Name=$Name}))) { throw 'Invalid power setting.' }
        $schemeId = $Path.Substring(10)
        $powerTarget = Get-PowerTarget $Name
        $output = Invoke-PowerCfg @('/qh', $schemeId, $powerTarget[0], $powerTarget[1])
        # The final two hexadecimal indexes are AC then DC, independent of UI language.
        $indexes = [regex]::Matches($output, '0x([0-9a-fA-F]{8})')
        $expectedCount = if ($Name -in @('AC','DC')) { 2 } else { 5 }
        if ($indexes.Count -ne $expectedCount) { throw 'Cannot reliably read power indexes; no guessed values will be used.' }
        $index = $indexes.Count - 2 + $powerTarget[2]
        $value = [Convert]::ToUInt32($indexes[$index].Groups[1].Value,16)
        if (-not (Test-PowerValue $Name $value)) { throw 'Unexpected power setting value.' }
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
    if (-not (Test-PowerEntry ([pscustomobject]@{Path=$Path;Name=$Name})) -or -not (Test-PowerValue $Name $Value)) { throw 'Invalid power setting.' }
    $schemeId = $Path.Substring(10)
    $powerTarget = Get-PowerTarget $Name
    $option = if ($powerTarget[2] -eq 0) { '/setacvalueindex' } else { '/setdcvalueindex' }
    Invoke-PowerCfg @($option, $schemeId, $powerTarget[0], $powerTarget[1], [string]$Value) | Out-Null
    # Refresh only if this is still the active plan. Restore does not switch plans.
    if ((Get-ActiveScheme) -eq $schemeId) { Invoke-PowerCfg @('/setactive', $schemeId) | Out-Null }
}

function Ensure-RegistryKey([string]$Path) {
    # Existing Windows keys must not be recreated. New-Item -Force can require
    # permissions beyond updating a value and can overwrite registry keys.
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
        New-Item -Path $Path -ErrorAction Stop | Out-Null
    }
}

$script:quietWorkbenchRoot=$PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if ($RestoreFrom) {
    $backup = Import-Clixml -LiteralPath $RestoreFrom
    if ($backup.Schema -ne 'ZenithStyle-v1' -or $backup.UserSid -ne $identity.User.Value -or $backup.Computer -ne $env:COMPUTERNAME) {
        throw 'Backup must belong to this computer and Windows user.'
    }
    # Only restore values managed by this script; validate the whole file first.
    foreach ($entry in $backup.Entries) {
        if (Test-PowerEntry $entry) {
            if ($UserSettingsOnly) { throw 'This backup includes power settings; omit -UserSettingsOnly when restoring it.' }
            if (-not $entry.Exists -or $entry.Kind -ne 'DWord' -or -not (Test-PowerValue $entry.Name $entry.Value)) { throw 'Invalid power backup value.' }
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
                $actionName = if ($entry.Name -in @('AC','DC')) { @('Do nothing','Sleep','Hibernate','Shut down')[[int]$entry.Value] } else { "$($entry.Value) seconds (zero means Never)" }
                $description = "Restore power setting ($($entry.Name)) to '$actionName' in the backed-up power plan."
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
                Ensure-RegistryKey $entry.Path
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
    $changed = -not $old.Exists -or $old.Kind -ne $setting.Kind -or $old.Value -ne $setting.Value
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
        if ($PSCmdlet.ShouldProcess("$($setting.Path) / $($setting.Name)", "$($setting.Label): set $($setting.Kind) to $($setting.Value)")) {
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
            $target = [pscustomobject]@{Exists=$true; Kind=$setting.Kind; Value=$setting.Value}
            $description = "$($setting.Label). $($explanations[$setting.Name])"
            Invoke-LoggedChange 'Apply' $description $before $target $backupPath {
            if ($setting.Name -eq 'AllowStorageSenseGlobal') {
                foreach ($protection in @('ConfigStorageSenseRecycleBinCleanupThreshold','ConfigStorageSenseDownloadsCleanupThreshold','ConfigStorageSenseCloudContentDehydrationThreshold')) {
                    $protectedValue = Read-Value $setting.Path $protection
                    if (-not $protectedValue.Exists -or $protectedValue.Kind -ne 'DWord' -or $protectedValue.Value -ne 0) {
                        throw 'Storage Sense was not enabled because a content-preservation setting was skipped or changed.'
                    }
                }
            }
            if (Test-PowerEntry $setting) {
                Set-LidValue $setting.Path $setting.Name $setting.Value
            } else {
            Ensure-RegistryKey $setting.Path
            New-ItemProperty -LiteralPath $setting.Path -Name $setting.Name -PropertyType $setting.Kind -Value $setting.Value -Force | Out-Null
            }
            $actual = Read-Value $setting.Path $setting.Name
            if (-not $actual.Exists -or $actual.Kind -ne $setting.Kind -or $actual.Value -ne $setting.Value) { throw "Verification failed: $($setting.Name)" }
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
