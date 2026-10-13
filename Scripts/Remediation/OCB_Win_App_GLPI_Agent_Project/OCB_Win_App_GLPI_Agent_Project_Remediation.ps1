#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Author: Omar Assaf
# X: omar_assaf
#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Please credit the author if you use this script
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
#
# This script will assign proper project code "GLPI"
# The list is updated in Azure with projects.
#
# ^**^**^**^**^**^**^**^**
# Start Transcript
# ^**^**^**^**^**^**^**^**
#
$TranscriptGlpi = "C:\ProgramData\MSF\Logs\Intune\Remediation\GLPI_Project_Update.log"
Start-Transcript -Path $TranscriptGlpi | Out-Null
#
# ^**^**^**^**^**^**^**^**
# Declare variables
# ^**^**^**^**^**^**^**^**
#
$RegPath = "HKLM:\SOFTWARE\GLPI-Agent"
$GLPIPath = "C:\Program Files\GLPI-Agent"
$PushUri = "http://localhost:62355/now"
$GLPIexe = "C:\Program Files (x86)\MSF\MSFAgent\MSFAgent.exe"
#
# ^**^**^**^**^**^**^**^**
# Main script
# ^**^**^**^**^**^**^**^**
#
# Match computer serial number to project code
$DeviceSN = (Get-WmiObject -class win32_bios).SerialNumber
$URI = "https://msfocbshare.blob.core.windows.net/ict-sd/data/ComputerName.csv"
# Fetch computer list data
$bytes = Invoke-WebRequest -Uri $URI -UseBasicParsing -Method Get | Select-Object -ExpandProperty Content
# Remove UTF-8 BOM if present (very safe - only removes if it really exists)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $bytes = $bytes[3..($bytes.Length-1)]
}
# Now convert bytes → string → objects
$ComputerListAsText = [System.Text.Encoding]::UTF8.GetString($bytes)
$ComputerList = $ComputerListAsText | ConvertFrom-Csv -ErrorAction Stop
# Get the project code that corresponds to current device
$ProjectCode = ($ComputerList | where-object Serial -EQ $DeviceSN).Project
#
# If project code is assigned continue the flow
If ($null -ne $ProjectCode){
    #
    # Set the System environment variables
    Write-Host "> Setting system environment variable to: $ProjectCode."
    [System.Environment]::SetEnvironmentVariable("MSFPROJECTCODE", $ProjectCode, "Machine")
    If (!(Test-Path $RegPath)) {
        New-Item -Path $RegPath -ErrorAction SilentlyContinue
        Write-Host "`n> Completed Creating GLPI Registry entries.`n"
    }
    Write-Host "> Updating registry string tag to: FIELDOCB$ProjectCode."
    $GlpiRegModify = New-ItemProperty -Path $RegPath -PropertyType String -Name "tag" -Value "FIELDOCB$ProjectCode" -Force
    $GlpiUpdatedPath = (($GlpiRegModify.PSPath).ToString()) -Replace "M.*::",""
    Write-Host "> Updated the following key: `n  Path = $GlpiUpdatedPath`n  tag = $($GlpiRegModify.tag)"
    # Restart GLPI service after modifying values if GLPI is running
    #
    #If GLPI exe is available then run it using available arguments
    If (Test-Path $GLPIexe){
        $GLPIArgs = @('/LOG=C:\ProgramData\MSF\Logs\GLPI_Agent_SetupExe.log','/VERYSILENT','/SUPPRESSMSGBOXES',"/PROJECTCODE=$ProjectCode")
        & $GLPIexe $GLPIArgs
        Start-Sleep -Seconds 30
        [System.Environment]::SetEnvironmentVariable("MSFPROJECTCODE", $ProjectCode, "Machine")
        # Initiate forced refresh of updated config to server
        Write-Host "> Initializing GLPI inventory."
        cmd /c "`"$GLPIPath\glpi-inventory.bat`" 1>nul 2>nul"
        Write-Host "> Sending updated values to GLPI server..."
        $GlpiWebRequest = Invoke-WebRequest -Uri $PushUri -UseBasicParsing -ErrorAction Continue
        $WebResultCode = $GlpiWebRequest.StatusCode
        $WebResultDscp = $GlpiWebRequest.StatusDescription
        Write-Host "> Web request push update returned code: $WebResultCode,`n> Description: $WebResultDscp"
        Write-Host "> Restarting GLPI Agent service."
        & $GLPIPath\glpi-restart.bat
        Write-Host "> Forcing GLPI Agent inventory update."
        Write-Host "`nOperation completed successfully"
    }
}
Else {
    Write-Output "No project code is assigned to $DeviceSN."
    }
Stop-Transcript | Out-Null
exit 0

