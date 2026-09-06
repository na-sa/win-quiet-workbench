# Quiet Workbench

Quiet Workbench is inspired by Microsoft's effort on Project Zenith to create a quieter, ready-to-code Windows experience. See Microsoft's announcement: [Announcing Project Zenith: The ready-to-code Windows experience on developer-class devices](https://blogs.windows.com/windowsdeveloper/2026/09/04/announcing-project-zenith-the-ready-to-code-windows-experience/).

This is an independent community project, not affiliated with, sponsored by, or endorsed by Microsoft. It applies selected Windows settings and does not install Project Zenith or reproduce its complete experience. Microsoft, Windows, and Project Zenith names are used only to identify the platform and the inspiration for this project.

**USE AT YOUR OWN RISK.** Review the preview and keep the backup. This script changes Windows preferences and laptop power behavior. A laptop running with its lid closed can drain its battery or overheat in a bag. Put it to sleep or shut it down before packing it away.

`Set-ZenithStyle.ps1` includes eight Explorer, Start, and long-path settings, plus two lid-close settings on detected laptops. This is a custom settings script, not an installation of Microsoft Project Zenith.

Each successful change prints `Setting applied - here's what it does:` followed by a plain-language explanation. It only says this after verifying the value. Restore prints `Setting restored` with its explanation.

Before the first actual apply change, the script saves its per-setting backup, then attempts to create a Windows System Restore point. It uses the bundled Windows PowerShell 5.1 runtime and verifies that a newly named restore point exists. The attempt and verified sequence number or failure reason are logged. It does not enable System Protection or bypass Windows restore-point frequency limits.

If System Restore is unavailable, disabled, lacks permission, fails, or does not produce a verifiable new point, the script explains the problem and asks whether to continue without one. Type `YES` to proceed using the per-setting backup. Any other response, an empty response, or unavailable interactive input stops before any setting changes. This also applies to a non-elevated `-UserSettingsOnly` run. Preview, `-WhatIf`, already-matching settings, and `-RestoreFrom` do not create restore points. Creating a point can take several minutes.

Laptop detection uses Windows chassis types (portable, laptop, notebook, sub-notebook, convertible, detachable). On detected laptops, the active power plan's lid-close action becomes **Do nothing** for both plugged-in and battery operation. Each is backed up, logged, and verified separately. Idle sleep timers, hibernation timers, and critical-battery protections remain unchanged: closing the lid alone will not trigger sleep, but those other conditions still can. Other power plans are not modified; switching ASUS performance modes may select another plan. Hardware-reported chassis types can be inaccurate. Desktops are skipped.

Run in 64-bit PowerShell from this folder:

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

- [Microsoft Project Zenith announcement](https://blogs.windows.com/windowsdeveloper/2026/09/04/announcing-project-zenith-the-ready-to-code-windows-experience/)
- [Microsoft Windows Developer Configuration](https://github.com/microsoft/WindowsDeveloperConfig/tree/main/windows-dev-config)
- [Windows 11 settings reference](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11)
- [Folder options registry mapping](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/3c837e92-016e-4148-86e5-b4f0381a757f)
- [Long-path support](https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation)
- [Lid-close actions](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action)
- [Powercfg commands](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options)
- [Windows chassis types](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-systemenclosure)
- [Windows restore-point creation and frequency limit](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1)
