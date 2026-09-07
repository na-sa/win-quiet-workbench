# Quiet Workbench

Quiet Workbench is inspired by Microsoft's effort on Project Zenith to create a quieter, ready-to-code Windows experience. See Microsoft's announcement: [Announcing Project Zenith: The ready-to-code Windows experience on developer-class devices](https://blogs.windows.com/windowsdeveloper/2026/09/04/announcing-project-zenith-the-ready-to-code-windows-experience/).

This is an independent community project, not affiliated with, sponsored by, or endorsed by Microsoft. It applies selected Windows settings and does not install Project Zenith or reproduce its complete experience. Microsoft, Windows, and Project Zenith names are used only to identify the platform and the inspiration for this project.

**USE AT YOUR OWN RISK.** Review the preview and keep the backup. This script changes Windows preferences and laptop power behavior. A laptop running with its lid closed can drain its battery or overheat in a bag. Put it to sleep or shut it down before packing it away.

`Set-ZenithStyle.ps1` includes eight Explorer, Start, and long-path settings, plus two lid-close settings on detected laptops. This is a custom settings script, not an installation of Microsoft Project Zenith.

## Settings applied

| # | Setting | What changes |
|---|---|---|
| 1 | Show file extensions | Shows suffixes such as `.txt` and `.ps1` so file types are visible. |
| 2 | Show hidden files and folders | Makes normally hidden items visible. Protected operating-system files remain hidden. |
| 3 | Show the full folder path | Displays the complete folder path in File Explorer's title bar. |
| 4 | Hide recent files | Hides the recent-files list in Explorer Home without deleting files. |
| 5 | Hide frequently used folders | Hides frequent folders in Explorer Home without deleting folders. |
| 6 | Disable Explorer sync-provider tips | Turns off sync-provider tips and promotional messages inside Explorer. |
| 7 | Disable Start tips and app recommendations | Turns off recommendations for tips, shortcuts, and new apps. This does not remove the entire Recommended section. |
| 8 | Enable long-path support | Allows compatible applications to use paths beyond the legacy 260-character limit. A reboot may be required. |
| 9 | Lid close: do nothing while plugged in | On detected laptops, closing the lid alone does not trigger sleep while using AC power. |
| 10 | Lid close: do nothing on battery | On detected laptops, closing the lid alone does not trigger sleep while using battery power. Battery use continues. |

The two lid-close settings apply to the active power plan only. Without -ServerOptions, idle sleep timers remain unchanged. Hibernation timers and critical-battery protections remain unchanged. Use `-SkipLidSettings` to omit these two changes, or `-UserSettingsOnly` to omit both lid-close settings and long-path support.

## Optional performance and distraction controls

The original ten settings remain the default. Add `-PerformanceOptions` to include five more settings, using the same backup, restore-point check, per-change logging, and verification:

| Optional setting | Effect and limitation |
|---|---|
| Reduce minimize/maximize animations | Reduces window transition effects; does not disable every animation in every app. |
| Disable taskbar animations | Reduces taskbar visual effects. |
| Disable transparency | Makes supported Windows surfaces opaque. |
| Disable Widgets | Uses the device-wide Allow widgets policy on supported Windows editions, including Windows 11 Pro. Applies to all users and requires administrator rights. The app package is not uninstalled. |
| Disable Search highlights | Reduces featured content in Search; preserves local search and does not globally disable web results. |

These primarily improve perceived responsiveness and reduce distractions. Performance gains depend on hardware and workload and have not been benchmarked. Sign out and back in before evaluating visual changes. Restore recognizes optional settings from its backup without requiring `-PerformanceOptions` again.

`-UserSettingsOnly` skips the device-wide Widgets policy. Direct writes to the former `TaskbarDa` preference were denied during live testing, so the preset now uses Microsoft's documented [Allow widgets policy](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-newsandinterests#allownewsandinterests). Windows edition support and organizational policies can affect whether it takes effect.

```powershell
# Preview baseline plus optional changes and the startup review
.\Set-ZenithStyle.ps1 -PerformanceOptions

# Apply baseline plus optional changes
.\Set-ZenithStyle.ps1 -Apply -PerformanceOptions

# Report startup registrations and indexing suggestions without applying changes
.\Set-ZenithStyle.ps1 -PerformanceReport

# Open Windows Search settings to choose indexing exclusions yourself
.\Set-ZenithStyle.ps1 -ReviewIndexing
```

**Startup configuration is never changed.** The report lists registered startup app names as potential contributors to login time and background resource use. Registration does not prove an app is enabled or running. Review actual startup impact in Task Manager. Common candidates include game launchers, optional desktop companions, local AI/container tools, and sync clients, depending on whether you need them at login. The report stays in the console and is not added to Git or change logs.

**Indexing is a guided review, not an automatic exclusion policy.** Use `-ReviewIndexing` to open Settings, then review Classic versus Enhanced indexing and exclude only generated build output, dependency folders, or large datasets you do not need to search. Exclusions can reduce indexing work but reduce search coverage. Keep useful documents and email indexed. This option does not change indexing scope or stop Windows Search. With `-WhatIf`, the Settings page is not opened.

References: [Microsoft performance guidance](https://support.microsoft.com/en-us/windows/tips-to-improve-pc-performance-in-windows-b3b3ef5b-5953-fb6a-2528-4bbed82fba96), [search indexing](https://support.microsoft.com/en-us/windows/experience/performance-optimization/search-indexing-in-windows), and [reducing visual distractions](https://support.microsoft.com/en-us/accessibility/windows/make-it-easier-to-focus-on-tasks).

## Optional server and development settings

These switches add to the baseline. They preview by default; add `-Apply` to make changes with backups, the restore-point check, per-change explanations, logs, and value verification.

| Switch | Settings and limits |
|---|---|
| `-ServerOptions` | Sets plugged-in idle sleep to Never and display timeout to 10 minutes in the active power plan. Enables End task in supported Windows 11 taskbar app menus. Using End task can lose unsaved work; the script itself does not terminate apps. |
| `-EnableDeveloperMode` | Enables the Windows Developer Mode preference. Use when needed by development tools. Does not enable Device Portal or remote discovery. Administrator rights required. |
| `-EnableStorageSense` | Enables automatic unused temporary-file cleanup while preserving Downloads, Recycle Bin contents, and local cloud-file availability. Keeps the existing cleanup schedule. Uses device policies supported on Pro, Enterprise, Education, and IoT Enterprise editions; administrator rights required. |
| `-ReviewNotifications` | Opens Notifications settings to choose Do not disturb rules and priority notifications yourself. No schedule is assumed. |
| `-ReviewIndexing` | Opens Search settings to select individual indexing exclusions yourself. |

Windows Update active hours and startup configuration are not configured. Notification schedules and indexing exclusions are guided reviews because they depend on your preferred hours and folders. `-WhatIf` suppresses opening either Settings page. Manual changes in Settings are not included in this script's backups or logs.

`-UserSettingsOnly` excludes the new machine policies and power timers, retaining the taskbar preference. `-SkipLidSettings` skips only lid-close settings, so it can be combined with `-ServerOptions` to change plugged-in timers without changing lid behavior. Battery timers, hibernation timers, manual sleep, and other power plans are unchanged. These options do not guarantee uninterrupted server uptime or improve compute throughput.

Storage Sense preservation policies are written before automatic cleanup is enabled, and verified again before enabling it. No cleanup is started by the script. **Restoring settings cannot recover files that Windows later deletes.** Policies can make the corresponding Settings controls managed. A backup restores the previous policy values, including removing values originally absent.

```powershell
# Preview the new settings
.\Set-ZenithStyle.ps1 -ServerOptions -EnableDeveloperMode -EnableStorageSense

# Simulate applying them without changing Windows
.\Set-ZenithStyle.ps1 -ServerOptions -EnableDeveloperMode -EnableStorageSense -Apply -WhatIf

# Apply the reviewed selection in an administrator PowerShell
.\Set-ZenithStyle.ps1 -ServerOptions -EnableDeveloperMode -EnableStorageSense -Apply

# Choose notification rules and indexing exclusions in Windows Settings
.\Set-ZenithStyle.ps1 -ReviewNotifications -ReviewIndexing
```

References: [Storage Sense policies](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-storage), [Developer Mode](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode), and [taskbar End task registry mapping](https://github.com/microsoft/winget-dsc/issues/171). Taskbar behavior varies by Windows build; registry verification does not prove the menu has refreshed.

## Development workload options

`-WorkloadOptions` selects the separate workload workflow. It does not reapply the original Windows baseline. Preview first, then apply in an administrator PowerShell:

```powershell
.\Set-ZenithStyle.ps1 -WorkloadOptions
.\Set-ZenithStyle.ps1 -WorkloadOptions -Apply -WhatIf
.\Set-ZenithStyle.ps1 -WorkloadOptions -Apply
```

For individual options and custom paths, use `Set-WorkloadOptions.ps1`:

| Switch | Behavior |
|---|---|
| `-CreateDevDrive` | Creates a new dynamic 100 GB VHDX at `%LOCALAPPDATA%\QuietWorkbench\DevDrive.vhdx`, formatted as a ReFS Dev Drive at `V:` with `Projects` and `Packages` folders. Requires the Hyper-V PowerShell module and Windows Dev Drive support. Never formats an existing disk or resizes physical partitions. |
| `-PrepareWslWorkspace` | Creates `~/projects` inside the selected distro's Linux filesystem. Default distro is Ubuntu. Uses that distro's default user; if it is root, the location is `/root/projects`. It does not create accounts, migrate repositories, change default users, or shut down WSL. |
| `-CheckOllamaGpu` | Checks the local Ollama server using the smallest installed model, or `-OllamaModel`. Generates a short response if the model is not loaded, then requires positive reported GPU memory allocation. If already loaded, inspects that allocation without changing its retention time. No model downloads or driver changes. CPU fallback produces a failure, not a success message. |
| `-DisableGameRecording` | Disables Game DVR, game app capture, and background recording for the current Windows user. Snipping Tool remains available. |
| `-ChromeMemorySaver` | Enables Memory Saver at the moderate level using per-user Chrome policies. Adds `localhost` and `127.0.0.1` tab-discard exceptions while preserving existing entries. Additional dashboard hostnames can be supplied with `-ChromeKeepAliveSites`. |
| `-ReviewChromeExtensions` | Reports extension folder counts by Chrome profile for manual review. Does not disable extensions or read browsing history. Presence does not establish resource use or enabled status. |

The storage switches prepare locations for **future projects**. Existing projects do not benefit until you choose to use those locations. Keep Windows builds on the Windows Dev Drive and Linux builds inside WSL. No package-manager cache paths are changed automatically. Dev Drive uses normal Windows trust and Defender behavior; no antivirus exclusions or filter removals are added. Performance depends on the workload and has not been benchmarked.

Storage defaults can be customized using `-DevDrivePath`, `-DevDriveLetter`, `-DevDriveSizeGB` (50 to 1024 GB), and `-WslDistro`. Existing VHDX files are accepted only if their adjacent Quiet Workbench manifest matches the disk identity, computer, user, path, size, and drive letter. Interrupted creation leaves the disk for inspection; rerunning will not reformat it. Keep the VHDX and its manifest together and outside synced folders. The script requires enough host free space for the maximum requested size plus 10 GB.

The VHDX expands as files are added. No startup mount task is installed. After a reboot, rerun `-CreateDevDrive -Apply` if the volume is not mounted. Provisioning or verification is logged on each explicit resource run. Registry preferences already at their targets are skipped.

```powershell
# Preview only Chrome and game recording preferences
.\Set-WorkloadOptions.ps1 -ChromeMemorySaver -DisableGameRecording

# Preserve a monitoring site along with local dashboards
.\Set-WorkloadOptions.ps1 -ChromeMemorySaver -ChromeKeepAliveSites localhost,127.0.0.1,monitor.example.com -Apply

# Restore registry preferences using the exact workload backup printed by the script
.\Set-WorkloadOptions.ps1 -RestoreFrom '.\zenith-backups\workloads-EXAMPLE.clixml'
```

Every apply first saves a workload backup and uses the same restore-point approval gate and JSON change logs as the baseline. Workload backups are restored with `Set-WorkloadOptions.ps1`, not the baseline restore switch. **Registry restore retains Dev Drive volumes, WSL folders, and all development files.** The adjacent `.quiet-workbench.clixml` file records Dev Drive provisioning state; System Restore is not a backup of future project data. To stop using a Dev Drive, close programs using it and detach its VHDX with `Dismount-VHD -Path '<exact VHDX path>'` in an administrator PowerShell. Preserve the VHDX until its contents are backed up. No automatic deletion is provided.

Chrome can report these policies as managed. Verify effective policies at `chrome://policy` after reloading policies, or after a browser restart. Organizational policies can override local choices. Only the listed hosts are added as exceptions; remote dashboards need their own hostnames. Extensions and startup configuration remain unchanged. The GPU check verifies allocation, not generation speed or whether the whole model fits in VRAM. A newly loaded diagnostic model is allowed to expire after 30 seconds.

References: [Microsoft Dev Drive](https://learn.microsoft.com/en-us/windows/dev-drive/), [WSL file placement](https://learn.microsoft.com/en-us/windows/dev-environment/wsl-interop), [Ollama API](https://docs.ollama.com/api), [Chrome Memory Saver](https://chromeenterprise.google/policies/high-efficiency-mode-enabled/), [savings level](https://chromeenterprise.google/policies/memory-saver-mode-savings/), and [tab-discard exceptions](https://chromeenterprise.google/policies/tab-discarding-exceptions/).

## Backups and execution

Each successful change prints `Setting applied - here's what it does:` followed by a plain-language explanation. It only says this after verifying the value. Restore prints `Setting restored` with its explanation.

Before the first actual apply change, the script saves its per-setting backup, then attempts to create a Windows System Restore point. It uses the bundled Windows PowerShell 5.1 runtime and verifies that a newly named restore point exists. The attempt and verified sequence number or failure reason are logged. It does not enable System Protection or bypass Windows restore-point frequency limits.

If System Restore is unavailable, disabled, lacks permission, fails, or does not produce a verifiable new point, the script explains the problem and asks whether to continue without one. Type `YES` to proceed using the per-setting backup. Any other response, an empty response, or unavailable interactive input stops before any setting changes. This also applies to a non-elevated `-UserSettingsOnly` run. Preview, `-WhatIf`, already-matching settings, and `-RestoreFrom` do not create restore points. Creating a point can take several minutes.

Laptop detection uses Windows chassis types (portable, laptop, notebook, sub-notebook, convertible, detachable). On detected laptops, the active power plan's lid-close action becomes **Do nothing** for both plugged-in and battery operation. Each is backed up, logged, and verified separately. Without -ServerOptions, idle sleep timers remain unchanged. Hibernation timers and critical-battery protections remain unchanged: closing the lid alone will not trigger sleep, but those other conditions still can. Other power plans are not modified; switching ASUS performance modes may select another plan. Hardware-reported chassis types can be inaccurate. Desktops are skipped.

Open 64-bit PowerShell as administrator under your usual Windows account, then change to the folder containing the script. Administrator PowerShell commonly starts in `C:\Windows\System32`, so navigate to your downloaded or cloned repository first.

If you see **"running scripts is disabled on this system"**, run the following command in that same PowerShell window before running the script:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
```

This permits local scripts for the current PowerShell process only. Closing the window discards this policy setting; it does not change the saved user or machine policy. The script cannot fix this error itself because Windows blocks it before any script code runs.

If a downloaded copy is still blocked because it is unsigned, review its contents and confirm it came from this repository before running `Unblock-File -LiteralPath .\Set-ZenithStyle.ps1`. That removes the downloaded-file marker from this specific file. If an organizational policy still blocks execution, use `Get-ExecutionPolicy -List` to identify it and contact your administrator.

Run from the folder containing the script:

```powershell
# Preview; does not change Windows
.\Set-ZenithStyle.ps1

# Apply in PowerShell opened as administrator under your usual account
.\Set-ZenithStyle.ps1 -Apply

# Or apply only the per-user settings without elevation
.\Set-ZenithStyle.ps1 -Apply -UserSettingsOnly

# Apply Windows preferences but skip laptop lid-close changes
.\Set-ZenithStyle.ps1 -Apply -SkipLidSettings

# Exercise the apply flow without writing values or a backup
.\Set-ZenithStyle.ps1 -Apply -WhatIf

# Restore using the exact backup path printed during application
.\Set-ZenithStyle.ps1 -RestoreFrom '.\zenith-backups\backup-EXAMPLE.clixml'
```

Each apply saves the prior values and their registry types before changing anything, including whether a value originally existed. Restore removes originally absent values, retaining any empty registry keys. Backups are specific to the computer and user. If several apply runs were made, restore their backups newest first to return to the original state. Keep backups private and only restore files you trust.

Every attempted apply or restore change also writes to a unique `zenith-logs/changes-*.log` file beside the script. The console prints its location. Each line is a JSON record containing a timestamp, a plain-language description of what the change does, the registry path and value name, previous and target values with their types, the backup path, and a `Started`, `Succeeded`, or `Failed` status. Success is recorded only after registry verification. Errors include their message. A lone `Started` entry means the operation was interrupted or its result could not be logged; inspect the setting before assuming success. If the initial log write fails, that change is not attempted. If a later log write fails, the script stops and reports the error; an already-written setting may need restoration.

For power settings, `SettingPath` identifies the power-plan GUID and `ValueName` is AC (plugged in) or DC (battery). Values mean 0 = Do nothing, 1 = Sleep, 2 = Hibernate, 3 = Shut down. Restore targets the plan recorded in the backup and does not switch to it if another plan is active. `-UserSettingsOnly` excludes both long paths and power settings. `-SkipLidSettings` affects apply/preview; restoring a backup still restores its recorded power settings.

Preview and `-WhatIf` do not create logs or change Windows. Settings already matching the target are shown in the preview table and skipped, so they produce no change entries.

The script verifies registry writes; Explorer/Start appearance still needs checking after signing out and back in. It does not restart Explorer or the PC. Windows updates or organizational policy may override preferences. Long paths require compatible applications and may need a reboot.

This first version does not configure the details pane, account notifications, Command Palette, taskbar pins, or install runtimes, VS Code, PowerToys, or WSL. Those remain follow-up work. It leaves protected system-file visibility, security controls, and global notifications unchanged.

## Test coverage

`tests/Test-Switches.ps1` exercises the complete script flow using a temporary copy with simulated registry, power-plan, restore-point, startup-query, and Settings-launch operations. Real backup files and JSON logs are created in an isolated temporary folder and removed afterward. Your Windows preferences and startup configuration are not changed by this suite.

Coverage includes default preview, `-Apply`, `-RestoreFrom`, `-UserSettingsOnly`, `-SkipLidSettings`, `-PerformanceOptions`, `-PerformanceReport`, `-ReviewIndexing`, `-WhatIf`, and `-Confirm` acceptance/decline. It checks rollback of missing and existing values, string types, log counts, idempotent reruns, and conflicting apply/restore arguments. The suite was run in Windows PowerShell 5.1 and PowerShell 7; interactive confirmation acceptance and decline were tested in Windows PowerShell 5.1 with supplied test responses.

```powershell
.\tests\Test-Switches.ps1
.\tests\Test-RegistryKey.ps1
.\tests\Test-PowerSettings.ps1
.\tests\Test-WorkloadOptions.ps1
# Interactive confirmation tests: answer A (Yes to All) or L (No to All)
.\tests\Test-Switches.ps1 -ConfirmCase
.\tests\Test-Switches.ps1 -ConfirmCase -Decline
```

`Test-RegistryKey.ps1` uses a disposable real HKCU registry key to verify key preservation. The original ten settings were also live-tested successfully on one Windows 11 PC. The automated switch tests do not establish that every visual effect works on every Windows build, that the indexing Settings page renders correctly, or that performance improves. Optional visual settings and full rollback still need live desktop acceptance testing.

The new server, Developer Mode, and Storage Sense switches were tested individually and together in Windows PowerShell 5.1 and PowerShell 7 using simulated apply, restore, WhatIf, logging, idempotency, and user-only filtering. Guided notification/indexing dispatch was tested with mocked launches. `Test-PowerSettings.ps1` exercises production parsing and command construction with simulated powercfg output, including distinct AC/DC values, malformed output, unsigned timeouts, and restoring an inactive plan. A read-only preview of all new settings also ran on the development machine. New settings have not been live-applied or evaluated for their UI effects.

## References

Workload tests run the full orchestration with simulated registry, disk provisioning, WSL, restore points, and GPU operations. They exercise preview, WhatIf, apply, restore, logs, exception preservation, and refusal after restore-point failure. Separate helper checks reject unsafe disk targets and unrelated restore entries and detect CPU fallback. These tests do not format a real disk or establish application performance. Live acceptance results are reported separately.

- [Microsoft Project Zenith announcement](https://blogs.windows.com/windowsdeveloper/2026/09/04/announcing-project-zenith-the-ready-to-code-windows-experience/)
- [Microsoft Windows Developer Configuration](https://github.com/microsoft/WindowsDeveloperConfig/tree/main/windows-dev-config)
- [Windows 11 settings reference](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11)
- [Folder options registry mapping](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/3c837e92-016e-4148-86e5-b4f0381a757f)
- [Long-path support](https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation)
- [Lid-close actions](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action)
- [Powercfg commands](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
- [Windows chassis types](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-systemenclosure)
- [Windows restore-point creation and frequency limit](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1)
