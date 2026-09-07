$script:changeLogPath = $null
function Write-ChangeLog {
    param($Operation, $Status, $Description, $Before, $Target, $BackupFile, $Detail)
    if (-not $script:changeLogPath) {
        $logDir = Join-Path $script:quietWorkbenchRoot 'zenith-logs'
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
        Write-ChangeLog $Operation 'Succeeded' $Description $Before $Target $BackupFile 'Operation completed and verified. Some application or shell settings may require a refresh.'
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
