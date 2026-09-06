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

The two lid-close settings apply to the active power plan only. Idle sleep timers, hibernation timers, and critical-battery protections remain unchanged. Use `-SkipLidSettings` to omit these two changes, or `-UserSettingsOnly` to omit both lid-close settings and long-path support.

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

## Backups and execution

Each successful change prints `Setting applied - here's what it does:` followed by a plain-language explanation. It only says this after verifying the value. Restore prints `Setting restored` with its explanation.

Before the first actual apply change, the script saves its per-setting backup, then attempts to create a Windows System Restore point. It uses the bundled Windows PowerShell 5.1 runtime and verifies that a newly named restore point exists. The attempt and verified sequence number or failure reason are logged. It does not enable System Protection or bypass Windows restore-point frequency limits.

If System Restore is unavailable, disabled, lacks permission, fails, or does not produce a verifiable new point, the script explains the problem and asks whether to continue without one. Type `YES` to proceed using the per-setting backup. Any other response, an empty response, or unavailable interactive input stops before any setting changes. This also applies to a non-elevated `-UserSettingsOnly` run. Preview, `-WhatIf`, already-matching settings, and `-RestoreFrom` do not create restore points. Creating a point can take several minutes.

Laptop detection uses Windows chassis types (portable, laptop, notebook, sub-notebook, convertible, detachable). On detected laptops, the active power plan's lid-close action becomes **Do nothing** for both plugged-in and battery operation. Each is backed up, logged, and verified separately. Idle sleep timers, hibernation timers, and critical-battery protections remain unchanged: closing the lid alone will not trigger sleep, but those other conditions still can. Other power plans are not modified; switching ASUS performance modes may select another plan. Hardware-reported chassis types can be inaccurate. Desktops are skipped.

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

Sources consulted September 6, 2026:

## Test coverage

`tests/Test-Switches.ps1` exercises the complete script flow using a temporary copy with simulated registry, power-plan, restore-point, startup-query, and Settings-launch operations. Real backup files and JSON logs are created in an isolated temporary folder and removed afterward. Your Windows preferences and startup configuration are not changed by this suite.

Coverage includes default preview, `-Apply`, `-RestoreFrom`, `-UserSettingsOnly`, `-SkipLidSettings`, `-PerformanceOptions`, `-PerformanceReport`, `-ReviewIndexing`, `-WhatIf`, and `-Confirm` acceptance/decline. It checks rollback of missing and existing values, string types, log counts, idempotent reruns, and conflicting apply/restore arguments. The suite was run in Windows PowerShell 5.1 and PowerShell 7; interactive confirmation acceptance and decline were tested in Windows PowerShell 5.1 with supplied test responses.

```powershell
.\tests\Test-Switches.ps1
.\tests\Test-RegistryKey.ps1
# Interactive confirmation tests: answer A (Yes to All) or L (No to All)
.\tests\Test-Switches.ps1 -ConfirmCase
.\tests\Test-Switches.ps1 -ConfirmCase -Decline
```

`Test-RegistryKey.ps1` uses a disposable real HKCU registry key to verify key preservation. The original ten settings were also live-tested successfully on one Windows 11 PC. The automated switch tests do not establish that every visual effect works on every Windows build, that the indexing Settings page renders correctly, or that performance improves. Optional visual settings and full rollback still need live desktop acceptance testing.

## References

- [Microsoft Project Zenith announcement](https://blogs.windows.com/windowsdeveloper/2026/09/04/announcing-project-zenith-the-ready-to-code-windows-experience/)
- [Microsoft Windows Developer Configuration](https://github.com/microsoft/WindowsDeveloperConfig/tree/main/windows-dev-config)
- [Windows 11 settings reference](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11)
- [Folder options registry mapping](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/3c837e92-016e-4148-86e5-b4f0381a757f)
- [Long-path support](https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation)
- [Lid-close actions](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action)
- [Powercfg commands](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
- [Windows chassis types](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-systemenclosure)
- [Windows restore-point creation and frequency limit](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1)
