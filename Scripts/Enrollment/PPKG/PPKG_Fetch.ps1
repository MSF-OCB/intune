#######################################################
## This will fetch always updated enrollment PPKG version
## Created by x: omar_assaf
########################################################



function Fun-RunAsAdmin {
    $currentPrincipal = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal.Groups -match 'S-1-5-32-544'  # Check if the user belongs to Administrators group
}

# Check if the script is running with admin privileges
if (-not (Fun-RunAsAdmin)) {
    # Load the Windows Forms assembly if it's not already loaded
    Add-Type -AssemblyName 'System.Windows.Forms'
    # Display a message box with custom error icon and message
    [System.Windows.Forms.MessageBox]::Show('This application needs to be run with elevated privilege', 'Require Admin', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
    <#
    # Relaunch the script as administrator
    $args = [System.String]::Join(' ', $myinvocation.MyCommand.Definition, $myinvocation.Line)
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command & { $args }" -Verb RunAs
    #>
}

Try {
    Start-Transcript -Path "C:\ProgramData\MSF\Logs\PPKG_Download.log" | Out-Null
} catch {
    Start-Transcript -Path "C:\ProgramData\MSF\Logs\PPKG_Download.log" | Out-Null
}
$ProgressPreference = 'SilentlyContinue'
if (Get-ProvisioningPackage) {
    Uninstall-ProvisioningPackage -AllInstalledPackages
    Write-Host "$(Get-Date) - Removed previously installed PPKGs"
}
do {
    Start-Sleep -Seconds 2
}
while (Get-ProvisioningPackage) {
}
$ProgressPreference = 'Continue'

# Enable TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    $PpkgEnrollUri = "https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Intune_Enroll.ppkg"
    $ExecFolder = "C:\Windows\MSF"
    if (!(Test-Path $ExecFolder)) {
        try {
            New-Item -ItemType Directory -Path "C:\Windows\MSF" -ErrorAction Stop | Out-Null
            Write-Host "$(Get-Date) - Created directory $ExecFolder"
        }
        catch {
            $_
            Stop-Transcript | Out-Null
            exit 1
        }
    }
    
    $GetprovisionPackage = Invoke-WebRequest -Method Get -Uri $PpkgEnrollUri -OutFile "C:\Windows\MSF\Intune_Enroll.ppkg" -UseBasicParsing -PassThru -ErrorAction Stop
    Write-Host "$(Get-Date) - Downloaded Intune provisioning package."
    $StatusCodePpkg = $GetprovisionPackage.StatusCode
} catch {
    Write-Host "Error: $_.Exception.Message" -ForegroundColor Red
}
# Install new package after it has been downloaded successfully
if ($StatusCodePpkg -eq "200") {
    try {
        # Remove any old uninstallation info
        $logDirectory = "C:\ProgramData\MSF\Logs"
        $newLogName = "PPKG_Install.zip"
        $newLogPath = Join-Path -Path $logDirectory -ChildPath $newLogName
        if (Test-Path -Path $newLogPath) {
            Remove-Item -Path $newLogPath -Force
            Write-Host "$(Get-Date) - Removed older Uninstall info"
        }
        # Start the installation of new Intune package
        Install-ProvisioningPackage -PackagePath "C:\Windows\MSF\Intune_Enroll.ppkg" -ForceInstall -QuietInstall -LogsDirectoryPath "C:\ProgramData\MSF\Logs" | Out-Null
        Write-Host "$(Get-Date) - Intune provisioning package installed."
        # retrive ppkg logs zip file and rename it properly
        $originalLogZip = Get-ChildItem -Path $logDirectory -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        #Rename the log file
        if ($originalLogZip) {
            $newLogPath = Join-Path -Path $logDirectory -ChildPath $newLogName
            # Rename the log file
            Rename-Item -Path $originalLogZip.FullName -NewName $newLogPath
        }

    } catch {
        Write-Error "An error occurred during the provisioning package installation: $_"
    }
} else {
    Write-Host "Failed to download Intune Provisioning Package." -ForegroundColor Red
}
$ProgressPreference = 'Continue'
Stop-Transcript | Out-Null
