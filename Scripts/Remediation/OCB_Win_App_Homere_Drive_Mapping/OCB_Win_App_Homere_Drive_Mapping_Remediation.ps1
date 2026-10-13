#########################################################################################
#   _______     ______  ______ _____            _____ _  _________ ______ _____ _    _ 
#  / ____\ \   / /  _ \|  ____|  __ \     /\   / ____| |/ /__   __|  ____/ ____| |  | |
# | |     \ \_/ /| |_) | |__  | |__) |   /  \ | |    | ' /   | |  | |__ | |    | |__| |
# | |      \   / |  _ <|  __| |  _  /   / /\ \| |    |  <    | |  |  __|| |    |  __  |
# | |____   | |  | |_) | |____| | \ \  / ____ \ |____| . \ _ | |  | |___| |____| |  | |
#  \_____|  |_|  |____/|______|_|  \_\/_/    \_\_____|_|\_(_)|_|  |______\_____|_|  |_|
#
#########################################################################################
# Authored by: Omar Assaf
# X: omar_assaf
# Please credit the author if you use this script
#########################################################################################



<#
.SYNOPSIS
    Create script to remediate Homere drive mapping to use SMB over QUIC.
#>

# Declare Variables
$HomereMappingVersion = "V7"
$CompanyName = "MSFOCB"
$NamePrefix = "Homere_Mapping"
$TaskSchdName = "$NamePrefix" + "_" + "$HomereMappingVersion"

$scriptFolder = "C:\Program Files (x86)\MSF\Homere"
$scriptPath = Join-Path $scriptFolder "$TaskSchdName.ps1"

# ============================================================
# Homere Deployment
# ============================================================

if (!(Test-Path $scriptFolder)) {
    New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null
}

# Check if the exact script already exists 
if (Test-Path -LiteralPath $scriptPath -PathType Leaf) { 
    Write-Host "Script already exists: $scriptPath" 
    Write-Host "Exiting without making any changes." 
    exit 0 
}

# Remove scheduled tasks
Get-ScheduledTask |
Where-Object { 
    $_.TaskName -like "$TaskSchdName*" -or 
    $_.TaskName -like "*Homere*" } |
ForEach-Object {
    Write-Host "Removing legacy scheduled task: $($_.TaskName)"
    Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false
}

Get-ChildItem -Path $scriptFolder -File -Recurse |
Where-Object {
    $_.Name -like "*$NamePrefix*" -or 
    $_.Name -like "*Homere*"
} | 
ForEach-Object {
    Write-Host "Removing legacy script: $($_.Name)"
    Remove-Item -LiteralPath $_.FullName -Force
}

Start-Sleep -Seconds 2

@'
#########################################################################################
#   _______     ______  ______ _____            _____ _  _________ ______ _____ _    _ 
#  / ____\ \   / /  _ \|  ____|  __ \     /\   / ____| |/ /__   __|  ____/ ____| |  | |
# | |     \ \_/ /| |_) | |__  | |__) |   /  \ | |    | ' /   | |  | |__ | |    | |__| |
# | |      \   / |  _ <|  __| |  _  /   / /\ \| |    |  <    | |  |  __|| |    |  __  |
# | |____   | |  | |_) | |____| | \ \  / ____ \ |____| . \ _ | |  | |___| |____| |  | |
#  \_____|  |_|  |____/|______|_|  \_\/_/    \_\_____|_|\_(_)|_|  |______\_____|_|  |_|
#
#########################################################################################
# Authored by: Omar Assaf
# X: omar_assaf
# Please credit the author if you use this script
#########################################################################################



<#
.SYNOPSIS
    Migrates the Homere network drive from legacy SMB to SMB over QUIC.
    No checks are performed to verify if the legacy mapping is still valid, it will be removed regardless.
#>

[CmdletBinding()]
param(
    [string]$DriveLetter = "R",
    [string]$FriendlyName = "Homere",
    [string]$Server = "homereshare.ocb.msf.org",
    [string]$ShareName = "Homere",
    [int]$MaxRetries = 3,
    [int]$RetryDelaySeconds = 2,
    [string]$LogPath = "c:\ProgramData\MSF\Logs\Intune\Remediation\Homere_Drive_Mapping.log"
)


#region Constants

$ProgressPreference = 'SilentlyContinue'
$TranscriptStarted = $false
$ready = $false
$NewRemotePath = "\\$Server\$ShareName"
$MountPoints2Base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2"
$UserNetworkBase = "HKCU:\Network"
$DrivePathWithSlash = "${DriveLetter}:\"

#####################################################################################################################

#region Log setup
try {
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) {
        New-Item $logDir -ItemType Directory -Force | Out-Null
    }
    Start-Transcript -Path $LogPath -Append -Force | Out-Null
    $TranscriptStarted = $true
}
catch {
    Write-Warning "Unable to start transcript."
    Write-Warning $_.Exception.Message
}
#endregion Log setup

#region Helper functions
#region Exit-Script
function Exit-Script {
    param(
        [int]$Code,
        [string]$Message
    )
    if ($Message) {
        Write-Output $Message
    }
    exit $Code
}
#endregion Exit-Script

#region Test-KerberosTicket
function Test-KerberosTicket {
    param(
        [Parameter(Mandatory)]
        [string]$Server
    )
    $klistPath = Join-Path $env:SystemRoot "System32\klist.exe"
    if (-not (Test-Path $klistPath)) {
        Write-Warning "klist.exe was not found at $klistPath. Skipping Kerberos ticket check."
        return $false
    }
    try {
        $tickets = & $klistPath tickets 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Unable to query the Kerberos ticket cache."
            return $false
        }
        $spn = "cifs/$Server"
        if ($tickets | Select-String -Pattern ([regex]::Escape($spn)) -Quiet) {
            Write-Host "Kerberos CIFS ticket found for $Server."
            return $true
        }
        Write-Warning "No Kerberos CIFS ticket found for $Server."
        return $false
    }
    catch {
        Write-Warning "Kerberos ticket check failed: $($_.Exception.Message)"
        return $false
    }
}

#endregion Test-KerberosTicket

#region Check server
function Test-SmbOverQuic {
    param (
        [Parameter(Mandatory)]
        [string]$Server
    )

    try {
        Resolve-DnsName $Server -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "Connectivity: DNS FAILED" -ForegroundColor Red
        throw "DNS resolution failed for $Server"
    }

    try {
        $udp = [System.Net.Sockets.UdpClient]::new()
        $udp.Connect($Server, 443)
        $udp.Send([byte[]]::new(0), 0) | Out-Null
        $udp.Close()

        Write-Host "Connectivity: OK" -ForegroundColor Green
    }
    catch {
        Write-Host "Connectivity: SMB over QUIC FAILED" -ForegroundColor Red
        throw "SMB over QUIC connectivity failed for $Server"
    }
}
#endregion Check server

#region Wait-ForDriveRelease
function Wait-ForDriveRelease {
    param(
        [string]$DriveLetter,
        [int]$TimeoutSeconds = 10
    )
    while ($TimeoutSeconds -gt 0) {
        $mapping = Get-SmbMapping `
            -LocalPath "${DriveLetter}:" `
            -ErrorAction SilentlyContinue

        if (-not $mapping) {
            return $true
        }
        Start-Sleep -Seconds 1
        $TimeoutSeconds--
    }
    Write-Warning "Timed out waiting for SMB mapping ${DriveLetter}: to be removed."
    return $false
}
#endregion Wait-ForDriveRelease

#region Send-DriveRefresh
function Send-DriveRefresh {
    param([string]$DrivePath)
    $pathPtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($DrivePath)
    try {
        [Win32.ShellNotify]::SHChangeNotify($SHCNE_DRIVEREMOVED, ($SHCNF_PATHW -bor $SHCNF_FLUSHNOWAIT), $pathPtr, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 300
        [Win32.ShellNotify]::SHChangeNotify($SHCNE_DRIVEADD, ($SHCNF_PATHW -bor $SHCNF_FLUSHNOWAIT), $pathPtr, [IntPtr]::Zero)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pathPtr)
    }
    Write-Host "Sent Explorer refresh for $DrivePath."
}
#endregion Send-DriveRefresh

#region Remove-Mapping
function Remove-DriveMapping {
    param(
        [Parameter(Mandatory)]
        [string]$DriveLetter,

        [Parameter(Mandatory)]
        [string]$RemotePath
    )

    Write-Host "--- Removing existing SMB mapping ---"

    Get-SmbMapping -ErrorAction SilentlyContinue |
    Where-Object {
        $_.LocalPath -eq "${DriveLetter}:" -or
        $_.RemotePath -eq $RemotePath
    } |
    Remove-SmbMapping -Force -UpdateProfile -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    Write-Host "--- Removing legacy net use mapping ---"

    cmd.exe /c "net use ${DriveLetter}: /delete /y" 2>&1 | Out-Null
    cmd.exe /c "net use $RemotePath /delete /y" 2>&1 | Out-Null
    cmd.exe /c "net use \\$Server /delete /y" 2>&1 | Out-Null


    Start-Sleep -Seconds 3

    # Remove persistent Explorer mapping
    Remove-Item `
        "$UserNetworkBase\$DriveLetter" `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    if (Get-SmbMapping -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LocalPath -eq "${DriveLetter}:" -or
            $_.RemotePath -eq $RemotePath
        }) {
        throw "Existing SMB mapping could not be removed."
    }

    if (-not (Wait-ForDriveRelease -DriveLetter $DriveLetter)) {
        Write-Warning "Drive ${DriveLetter}: is still reported as active."
    }

    Write-Host "--- Cleanup complete ---"
}
#endregion Remove-Mapping

#region New-QuicDriveMapping
function New-QuicDriveMapping {

    param(
        [string]$DriveLetter,
        [string]$RemotePath,
        [string]$UserPrincipleName,
        [int]$Retries = 3,
        [int]$RetryDelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            $mapping = New-SmbMapping `
                -LocalPath "${DriveLetter}:" `
                -RemotePath $RemotePath `
                -TransportType QUIC `
                -Persistent $true `
                -UserName $UserPrincipleName `
                -ErrorAction Stop
            Write-Host "SMB mapping created successfully."
            return $mapping
        }
        catch {
            Write-Warning "Attempt $attempt failed."
            Write-Warning $_.Exception.Message
            if ($attempt -eq $Retries) {
                throw
            }
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}
#endregion New-QuicDriveMapping
#endregion Helper functions
#-----------------------------------------------------------------

#region Shell32 interop
if (-not ('Win32.ShellNotify' -as [type])) {
    Add-Type -MemberDefinition @"
        [DllImport("shell32.dll")]
        public static extern void SHChangeNotify(long wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
"@ -Name ShellNotify -Namespace Win32 | Out-Null
}

$SHCNE_DRIVEADD = 0x00000100
$SHCNE_DRIVEREMOVED = 0x00000200
$SHCNF_PATHW = 0x0005
$SHCNF_FLUSHNOWAIT = 0x1000
#endregion Shell32 interop

#region Exceution
try {
    #region PreCheck context
    Write-Host "--------------------------------"
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $UserPrincipleName = (whoami.exe /upn 2>$null).Trim()

    Write-Host "Running as: $($currentIdentity.Name) (SID: $($currentIdentity.User.Value))"
    Write-Host "User Principal Name: $UserPrincipleName"
    if ($currentIdentity.User.Value -eq 'S-1-5-18' -or $currentIdentity.Name -match '^NT AUTHORITY\\') {
        Exit-Script -Code 2 -Message "This script must run in the interactive user's context."
    }
    #endregion PreCheck context

    # Check connectivity
    #Test-SmbOverQuic -Server $Server -ErrorAction Stop

    #check current mapping
    $current = Get-SmbMapping `
        -LocalPath "${DriveLetter}:" `
        -ErrorAction SilentlyContinue
    
    $currentRemote = Get-SmbMapping `
        -RemotePath $NewRemotePath `
        -ErrorAction SilentlyContinue    

    $mappingCorrect = (
        @($current).Count -eq 1 -and
        @($currentRemote).Count -eq 1 -and
        $current.LocalPath -eq "${DriveLetter}:" -and
        $current.RemotePath -eq $NewRemotePath -and
        $current.Status -eq "OK" -and
        $currentRemote.LocalPath -eq "${DriveLetter}:"
    )

    $pathAccessible = Test-Path "${DriveLetter}:\" -PathType Container

    if ($mappingCorrect -and $pathAccessible) {
        Write-Host "Drive already correctly mapped."
    }
    else {
        #region Connectivity diagnostics
        Write-Host "Drive mapping needs to be updated."
        Write-Host "===== Connectivity diagnostics ====="

        Test-SmbOverQuic -Server $Server -ErrorAction Stop

        #endregion Connectivity diagnostics
        Remove-DriveMapping -DriveLetter $DriveLetter -RemotePath $NewRemotePath

        if (-not (Test-KerberosTicket -Server $Server)) {
            Write-Warning "No Kerberos CIFS ticket found for $Server. Continuing with SMB mapping."
        }

        $mapping = New-QuicDriveMapping `
            -DriveLetter $DriveLetter `
            -RemotePath $NewRemotePath `
            -UserPrincipleName $UserPrincipleName `
            -Retries $MaxRetries `
            -RetryDelaySeconds $RetryDelaySeconds
    
        Start-Sleep -Seconds 3

        for ($i = 0; $i -lt 20; $i++) {
            $current = Get-SmbMapping `
                -LocalPath "${DriveLetter}:" `
                -ErrorAction SilentlyContinue

            if (
                @($current).Count -eq 1 -and
                $current.Status -eq "OK" -and
                (Test-Path "${DriveLetter}:\" -PathType Container)
            ) {
                $ready = $true
                break
            }
            Start-Sleep -Seconds 1
        }

        Send-DriveRefresh -DrivePath $DrivePathWithSlash
        
        if (-not $ready) {
            throw "Timed out waiting for ${DriveLetter}: to become available."
        }
    }

    # Set Friendly Name only if required
    $MapPointKey = Get-ChildItem $MountPoints2Base -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -ieq "##$Server#$ShareName" } |
    Select-Object -First 1 -ExpandProperty PSPath

    if (-not $MapPointKey) {
        $MapPointKey = "$MountPoints2Base\##$Server#$ShareName"
        New-Item -Path $MapPointKey -Force | Out-Null
    }

    $currentLabel = Get-ItemProperty `
        -Path $MapPointKey `
        -Name "_LabelFromReg" `
        -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty "_LabelFromReg" -ErrorAction SilentlyContinue

    if ($currentLabel -ne $FriendlyName) {
        New-ItemProperty `
            -Path $MapPointKey `
            -Name "_LabelFromReg" `
            -Value $FriendlyName `
            -PropertyType String `
            -Force | Out-Null

        $ready = $true
        Send-DriveRefresh -DrivePath $DrivePathWithSlash
        Write-Host "Updated drive label to '$FriendlyName'."
    }
    else {
        Write-Host "Drive label already set to '$FriendlyName'."
    }

    # Final Explorer refresh
    $explorer = Get-Process explorer -ErrorAction SilentlyContinue
    if ($ready -and $explorer) {
        Start-Sleep -Seconds 2
        Send-DriveRefresh -DrivePath $DrivePathWithSlash
        Write-Host "Restarting Explorer shell."
        Stop-Process `
            -Name explorer `
            -Force `
            -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    else {
        Write-Host "No need to restart Explorer shell."
    }

    Exit-Script -Code 0 -Message "Homere drive mapping script completed successfully."
}
catch {
    Write-Warning $_.Exception.Message
    Exit-Script -Code 1 -Message "Homere drive mapping script failed."
}
finally {
    if ($TranscriptStarted) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
}
'@ | Set-Content -Path $scriptPath -Encoding UTF8
Write-Host "Homere drive mapping script created at: $scriptPath"


# ------------------------------------------------------------------------------------------------------- #
# Create Scheduled Task to run At Logon
# ------------------------------------------------------------------------------------------------------- #
#

$XMLSTRING = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>2026-08-03T22:33:05.7079102</Date>
    <Author>$CompanyName</Author>
    <URI>\$CompanyName\$TaskSchdName</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT30S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command>
      <Arguments>-WindowStyle Hidden -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "$scriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Register-ScheduledTask -TaskName $TaskSchdName -Xml $XMLSTRING -TaskPath "\$CompanyName" -Force | Out-Null
Write-Host "Scheduled task '$TaskSchdName' created successfully."
Write-Host "Homere script and scheduled task setup completed."
