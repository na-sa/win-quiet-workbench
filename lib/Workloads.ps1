function Read-WorkloadRegistry($Path,$Name) {
    $key=Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    $exists=$null -ne $key -and $key.GetValueNames() -contains $Name
    $value=$null; $kind=$null
    if ($exists) { $value=$key.GetValue($Name); $kind=$key.GetValueKind($Name).ToString() }
    [pscustomobject]@{Path=$Path;Name=$Name;Exists=$exists;Kind=$kind;Value=$value}
}
function Ensure-WorkloadRegistryKey($Path) {
    if (Test-Path -LiteralPath $Path) { return }
    $parent=Split-Path -Path $Path -Parent
    if (-not $parent -or $parent -eq $Path) { throw 'Cannot locate the registry parent.' }
    Ensure-WorkloadRegistryKey $parent
    New-Item -Path $Path -ErrorAction Stop | Out-Null
}
function Set-WorkloadRegistry($Path,$Name,$Kind,$Value) {
    Ensure-WorkloadRegistryKey $Path
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Kind -Value $Value -Force | Out-Null
}
function Test-WorkloadRegistryEntry($Entry) {
    $allowed=($Entry.Path -eq 'HKCU:\System\GameConfigStore' -and $Entry.Name -eq 'GameDVR_Enabled') -or
        ($Entry.Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -and $Entry.Name -in @('AppCaptureEnabled','HistoricalCaptureEnabled')) -or
        ($Entry.Path -eq 'HKCU:\Software\Policies\Google\Chrome' -and $Entry.Name -in @('HighEfficiencyModeEnabled','MemorySaverModeSavings'))
    $exception=$Entry.Path -eq 'HKCU:\Software\Policies\Google\Chrome\TabDiscardingExceptions' -and $Entry.Name -match '^[1-9][0-9]*$'
    if (-not ($allowed -or $exception)) { return $false }
    if (-not $Entry.Exists) { return $true }
    if ($exception) { return $Entry.Kind -eq 'String' -and $Entry.Value -is [string] }
    return $Entry.Kind -eq 'DWord' -and ($Entry.Value -is [int] -or $Entry.Value -is [uint32])
}
function Test-DevDriveRequest($Path,$Letter,$SizeGB) {
    if ($Path -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($Path) -ne '.vhdx' -or $Path -match '["\r\n]') { throw 'DevDrivePath must be an absolute local .vhdx path.' }
    if ($Letter -notmatch '^[D-Z]$' -or $SizeGB -lt 50 -or $SizeGB -gt 1024) { throw 'Invalid Dev Drive letter or size.' }
    foreach ($cloudRoot in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)) {
        if ($cloudRoot -and [IO.Path]::GetFullPath($Path).StartsWith($cloudRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Store the Dev Drive outside OneDrive.' }
    }
    if (-not (Get-Command Format-Volume).Parameters.ContainsKey('DevDrive')) { throw 'This Windows version does not support Format-Volume -DevDrive.' }
    Get-Command New-VHD,Get-VHD,Mount-VHD -ErrorAction Stop | Out-Null
    if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath ($Path+'.quiet-workbench.clixml'))) { throw 'Existing VHDX has no Quiet Workbench ownership manifest; it will not be modified.' }
    if (-not (Test-Path -LiteralPath $Path) -and (Get-PSDrive -Name $Letter -ErrorAction SilentlyContinue)) { throw "Drive letter ${Letter}: is already in use." }
}
function Assert-WorkbenchDisk($Vhd,$Disk) {
    if (-not $Vhd.Attached -or $Vhd.DiskNumber -ne $Disk.Number -or $Disk.IsBoot -or $Disk.IsSystem -or $Disk.PartitionStyle -ne 'RAW') {
        throw 'Refusing to initialize or format anything except the newly attached RAW virtual disk.'
    }
}
function Ensure-WorkbenchDevDrive($Path,$Letter,$SizeGB) {
    Test-DevDriveRequest $Path $Letter $SizeGB
    $Path=[IO.Path]::GetFullPath($Path)
    $manifestPath=$Path+'.quiet-workbench.clixml'
    $newDisk=-not (Test-Path -LiteralPath $Path)
    if ($newDisk) {
        $hostVolume=Get-Volume -DriveLetter $Path.Substring(0,1)
        if ($hostVolume.SizeRemaining -lt ($SizeGB+10)*1GB) { throw 'Insufficient free space for the maximum Dev Drive size plus 10 GB reserve.' }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
        $manifest=[pscustomobject]@{Schema='QuietWorkbenchDevDrive-v1';Computer=$env:COMPUTERNAME;UserSid=$identity.User.Value;Path=$Path;Letter=$Letter;SizeGB=$SizeGB;DiskIdentifier=$null;Status='Planned'}
        $manifest | Export-Clixml -LiteralPath $manifestPath
        $vhd=New-VHD -Path $Path -SizeBytes ($SizeGB*1GB) -Dynamic -ErrorAction Stop
        $manifest.DiskIdentifier=[string]$vhd.DiskIdentifier
        $manifest.Status='Created'
        $manifest | Export-Clixml -LiteralPath $manifestPath
        Mount-VHD -Path $Path -ErrorAction Stop
        $vhd=Get-VHD -Path $Path
        $disk=Get-Disk -Number $vhd.DiskNumber
        Assert-WorkbenchDisk $vhd $disk
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction Stop | Out-Null
        $partition=New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $Letter -ErrorAction Stop
        # The partition object originates only from the newly created VHD above.
        $partition | Format-Volume -DevDrive -FileSystem ReFS -NewFileSystemLabel 'QuietWorkbench' -Confirm:$false -ErrorAction Stop | Out-Null
        $manifest.Status='Formatted'
        $manifest | Export-Clixml -LiteralPath $manifestPath
    } else {
        $manifest=Import-Clixml -LiteralPath $manifestPath
        if ($manifest.Schema -ne 'QuietWorkbenchDevDrive-v1' -or $manifest.Computer -ne $env:COMPUTERNAME -or $manifest.UserSid -ne $identity.User.Value -or $manifest.Path -ne $Path -or $manifest.Letter -ne $Letter -or $manifest.SizeGB -ne $SizeGB -or $manifest.Status -ne 'Formatted') { throw 'Dev Drive manifest mismatch or incomplete provisioning. Existing disk retained for inspection.' }
        $vhd=Get-VHD -Path $Path
        if ([string]$vhd.DiskIdentifier -ne $manifest.DiskIdentifier) { throw 'Virtual disk identity differs from the ownership manifest.' }
        if (-not $vhd.Attached) {
            if (Get-PSDrive -Name $Letter -ErrorAction SilentlyContinue) { throw 'Requested drive letter is occupied.' }
            Mount-VHD -Path $Path -ErrorAction Stop
        }
    }
    $vhd=Get-VHD -Path $Path
    $partition=Get-Partition -DiskNumber $vhd.DiskNumber | Where-Object DriveLetter -eq $Letter
    if (@($partition).Count -ne 1) { throw 'The mounted Dev Drive does not have the expected drive letter.' }
    $volume=$partition | Get-Volume
    if ($volume.FileSystem -ne 'ReFS' -or $volume.FileSystemLabel -ne 'QuietWorkbench') { throw 'Dev Drive volume verification failed.' }
    $devInfo=& "$env:SystemRoot\System32\fsutil.exe" devdrv query "${Letter}:" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Dev Drive verification failed: $devInfo" }
    foreach ($name in @('Projects','Packages')) { [IO.Directory]::CreateDirectory("${Letter}:\$name") | Out-Null }
    Write-Host "Verified Dev Drive: ${Letter}:\Projects and ${Letter}:\Packages. Re-run -CreateDevDrive -Apply to mount it after reboot if needed."
}
function Invoke-WorkbenchWsl($Distro,$Command) {
    # Avoid differences in nested quoting between Windows PowerShell 5.1 and 7.
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Command))
    $result=& "$env:SystemRoot\System32\wsl.exe" --distribution $Distro --exec sh -c "echo $encoded | base64 -d | sh" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "WSL command failed: $result" }
    ($result -join "`n").Trim()
}
function Ensure-WslWorkspace($Distro) {
    # Static shell text, with no interpolation of Windows paths or user input.
    $details=Invoke-WorkbenchWsl $Distro 'set -eu; test ! -L "$HOME/projects"; test "$(stat -f -c %T "$HOME")" = ext2/ext3; mkdir -p "$HOME/projects"; test "$(stat -f -c %T "$HOME/projects")" = ext2/ext3; printf "%s\n" "$HOME/projects"'
    Write-Host "Verified Linux filesystem workspace: $Distro : $details"
}
function Test-OllamaGpu($Model) {
    $base='http://127.0.0.1:11434'
    $tags=Invoke-RestMethod "$base/api/tags" -TimeoutSec 15
    $models=@($tags.models)
    if (-not $models.Count) { throw 'No installed Ollama models. No model was downloaded.' }
    if (-not $Model) { $Model=($models | Sort-Object size | Select-Object -First 1).name }
    if ($models.name -notcontains $Model) { throw 'The selected model is not installed. No download was attempted.' }
    $running=Invoke-RestMethod "$base/api/ps" -TimeoutSec 15
    # Avoid changing an already-loaded model's retention time or interrupting work.
    $existing=@($running.models | Where-Object name -eq $Model)
    if ($existing.Count) {
        $loaded=$existing[0]
    } else {
        $body=@{model=$Model;prompt='Reply with only OK.';stream=$false;keep_alive='30s';options=@{num_predict=8;num_ctx=512}} | ConvertTo-Json -Depth 4
        $response=Invoke-RestMethod "$base/api/generate" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
        if (-not $response.done) { throw 'Ollama generation did not finish.' }
        $running=Invoke-RestMethod "$base/api/ps" -TimeoutSec 15
        $loaded=@($running.models | Where-Object name -eq $Model) | Select-Object -First 1
    }
    if (-not $loaded -or -not $loaded.PSObject.Properties['size_vram'] -or [long]$loaded.size_vram -le 0) { throw 'Ollama did not report GPU memory allocation. CPU fallback or an unsupported model requires investigation.' }
    $fraction=if ([long]$loaded.size -gt 0) { [math]::Round(100*[double]$loaded.size_vram/[double]$loaded.size,1) } else { 0 }
    Write-Host "Verified Ollama GPU allocation: $Model, $([math]::Round($loaded.size_vram/1GB,2)) GB in GPU memory ($fraction percent of reported model allocation). This is not a throughput benchmark."
}
function Show-ChromeExtensionReport {
    $root=Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    $profiles=@(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object Name -match '^(Default|Profile [0-9]+)$')
    foreach ($profile in $profiles) {
        $extensions=@(Get-ChildItem -LiteralPath (Join-Path $profile.FullName 'Extensions') -Directory -ErrorAction SilentlyContinue)
        Write-Host "Chrome $($profile.Name): $($extensions.Count) extension folders to review. Presence does not prove an extension is enabled or consuming resources."
    }
    Write-Host 'Review extensions in chrome://extensions and their CPU use in Chrome Task Manager. No extension or startup configuration is changed.'
}
