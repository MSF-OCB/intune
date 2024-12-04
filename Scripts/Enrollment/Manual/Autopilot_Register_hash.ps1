#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Author: Omar Assaf
# X: omar_assaf
#
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
# Please credit the author if you use this script
#^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**^**
#
# This script will upload Hardware Hash for Autopilot devices
# You will be requested to sign in with you Admin Account
#

function FunPreReqInstall {
    # Check if NuGet is installed, if not install it silently
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Host "Installing NuGet package provider..." -ForegroundColor Yellow
        Install-PackageProvider -Name NuGet -Force -Confirm:$false | Out-Null
    }else {
        Write-Host ">> NuGet package provider is already installed."
    }
}



function FunConnectGraphforAuth {
    # Check if MS Graph authentication exist
    if (!(Get-Module -ListAvailable microsoft.graph.authentication)) {
        Write-Host ">> Installing module microsoft.graph.authentication"
        Install-Module microsoft.graph.authentication -Force -ErrorAction Ignore
    }
    # add scopes that you need for machines
    try {
        Connect-MgGraph -ContextScope Process -NoWelcome -Scopes "DeviceManagementServiceConfig.ReadWrite.All" -ErrorActio Stop
        # make sure to add the -erroractio to STOP, so it can use CATCH errors
    }
    catch {
        # Check if the error is related to authentication failure (e.g., user canceled)
        if ($_ -match "InteractiveBrowserCredential authentication failed: User canceled authentication") {
            Write-Host ">> Authentication failed: User canceled the login process." -ForegroundColor Red
            Exit 1 # the script with a non-zero exit code indicating failure
        }
        else {
            # Handle other potential errors
            Write-Error ">> An unexpected error occurred: $_"
            Exit 2 #
        }
    }
    Set-MgRequestContext -MaxRetry 5 -RetryDelay 10 > $null
    Write-Host ">> You are connected to Tenant: $((Get-MgContext).TenantId)" -ForegroundColor Green
    Write-Host ">> You are connected as: $((Get-MgContext).Account)" -ForegroundColor Green
}



function FunCheckAutopilotDevice {
    $Path = "deviceManagement/windowsAutopilotDeviceIdentities"
    $Destination = $uri + $Path + "?`$filter=contains(serialNumber,'$DeviceSerialNumber')"
    $AutoPilotinfo = Invoke-MgGraphRequest -Uri $Destination -Method Get -OutputType PSObject
    $AutoPilotinfo.value    
}



function FunImportAutopilotDevice {
    Write-Host ">> Initiating import process of new Autopilot device."
    # Define the device data that will be registered during importation 
    $deviceRegistrationData = @{
        "serialNumber" = "$DeviceSerialNumber"
        "hardwareIdentifier" = $DeviceHardwareHash   
        "groupTag" = "$OrderTag" 
    }
    # Convert the device registration data to JSON
    $body = $deviceRegistrationData | ConvertTo-Json #-Depth 5
    try {
        # Send the request to Intune Autopilot API
        $Path = "deviceManagement/importedWindowsAutopilotDeviceIdentities"
        $AutopilotImportResp = Invoke-MgGraphRequest -Method POST -Uri "$uri$Path" -Body $body -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        Write-Host "$_.Exception.Message" -ForegroundColor Red
        Write-Host ">> Cannot import device to Autopilot" -ForegroundColor Red
        FunCleanExit
    }
    return $AutopilotImportResp
}



function FunGetAutopilotImportStat {
    $Path = "deviceManagement/importedWindowsAutopilotDeviceIdentities"
    #$Destination = $uri + $Path + "?`$filter=serialNumber eq '$DeviceSerialNumber'"
    # $Destination = $uri + $Path + "/$($(FunImportAutopilotDevice).importId)"
    $Destination = $uri + $Path + "/$AutopilotImportRefId"
    $AutopilotImportResp = Invoke-MgGraphRequest -Method GET -Uri $Destination -OutputType PSObject
    ## $Output = $AutopilotImportResp.value.state
    return $AutopilotImportResp
}



function FunGetOperationDuration {
    $OperationEndTime = Get-Date
    $OverallDuration = $OperationEndTime - $OperationStartTime
    Write-Host ">> Total time for this device is: $($OverallDuration.Minutes) min $($OverallDuration.Seconds) sec $($OverallDuration.Millisecond) ms"
}



function FunUpdateAutopilotDevice {
    Write-Host ">> Updating Autopilot device properties in Intune."
    $Path = "deviceManagement/windowsAutopilotDeviceIdentities"
    $Destination = $uri + $Path + "/$($(FunCheckAutopilotDevice).id)" + "/updateDeviceProperties"
    if ($DeviceOfficeLoc -eq 1) {
        $body = @{
            "groupTag" = "$OrderTag"
            "displayName" = $DeviceGeneratedName
        } | ConvertTo-Json -Depth 5
    }
    elseif ($DeviceOfficeLoc -eq "2") {
        $body = @{
            "groupTag" = "$OrderTag"
            "displayName" = $DeviceGeneratedName
        } | ConvertTo-Json -Depth 5
    }
    Invoke-MgGraphRequest -Method POST -Uri $Destination -Body $body -ContentType "application/json"
}



function FunAutopilotDeviceSync {
    Write-Host ">> Synchronizing Autopilot imported devices to Intune portal"
    $Path = "deviceManagement/windowsAutopilotSettings"
    $Destination = $UriBeta + $Path + "/sync"
    try {
        Invoke-MgGraphRequest -Method POST -Uri $Destination -StatusCodeVariable AutopilotSyncHttpCode -ErrorAction Stop
    }catch{
        Write-Host ">> Error synchronizing Autopilot to Intune $_"
    }
    if ($AutopilotSyncHttpCode -eq "200") {
       Write-Host ">> Response: 200 - initiating sync between Autopilot and Intune started, you might need up to 10 minutes to see the device."
    }
    else {
        Write-Warning "Syncing could not be initiated now as too many requests, please wait 10 minutes."
    }
}



function FunCleanExit {
    if ($null -ne $(Get-MgContext)) {
        Disconnect-MgGraph    
    }
    if (Test-Path "$env:USERPROFILE\.mg") {
        Remove-Item "$env:USERPROFILE\.mg" -Recurse -Force
    }
    Write-Warning "Your sessions had been closed"
    Exit 999
}



function FunDeviceHashExtract {
    # Define the CIM session
    $session = New-CimSession

    # Define the namespace and class to query
    $namespace = "root/cimv2/mdm/dmmap"
    $class = "MDM_DevDetail_Ext01"
    $filter = "InstanceID='Ext' AND ParentID='./DevDetail'"  # Adjust filter as needed
    try {
         # Get the CIM instance for device details
        $deviceDetails = Get-CimInstance -CimSession $session -Namespace $namespace -ClassName $class -Filter $filter -ErrorAction Stop
    }
    catch {
        Write-Host ">> Error: Hardware Hash is not available. Exiting..." -ForegroundColor Red
        Write-Host ">> Cannot continue: $_" -ForegroundColor Red
        exit 1
    }

    # Check if we have any results
    if ($deviceDetails) {
        # Extract hardware hash (assuming it's a property of MDM_DevDetail_Ext01)
        $hardwareHash = $deviceDetails.DeviceHardwareData
        # Check if hardware hash exists
        if ($hardwareHash) {
            # Write-Host "Hardware Hash: $hardwareHash"
            Write-Host ">> Good! Hardware Hash is available"
        }
        else {
            Write-Host ">> Hardware hash cannot be extracted" -ForegroundColor Red
            FunCleanExit
        }
    }
    else {
        Write-Host "`n>> Fatal error: No hardware 4k hash exist on this device." -ForegroundColor Red
        FunCleanExit
    }

    $session | Remove-CimSession
    $hardwareHash
}



#######################################################################################################################
#
#######################################################################################################################



function FunGet-CountryISO {
    $IPInfoUri = "https://ipinfo.io/json"
    # Get location information from the IP geolocation API
    $response = Invoke-RestMethod -Uri $IPInfoUri -Method Get -UseBasicParsing
    
    # Extract the country code (ISO 2-letter)
    $countryCode = $response.country

    if (-not $countryCode) {
        Write-Host "Country code not found."
        Break
    }
    return $countryCode
}


function FunGenHQNaming {
    if ($env:computername -ilike "OCBL*") {
        Write-Host "`n$env:computername meets OCB naming convention, proceeding...`n" -Foreground Green -BackgroundColor Black
    }
    else {
        Write-Host "Computer Name must meet OCB naming convention before proceeding." -Foreground Red -BackgroundColor Black
        Write-Host "Once computername is set properly, the process will continue automatically.`n" -Foreground Magenta -BackgroundColor Black
        Write-Host "Instructions: Computer Asset name must contain ONLY:" -Foreground Magenta -BackgroundColor Black
        Write-Host "* OCBL prefix is added automatically, don not add it. `n* 12 characters max. `n* Upper Case Letters or Numbers ONLY. `n* No special characters or space." -Foreground Yellow -BackgroundColor Black
        Do {
            try {
                [ValidatePattern("^[A-Z0-9]{1,12}$", Options = 'None')]$DeviceNameInput = Read-Host "Enter computer asset (without OCBL)"
                Write-Host "Name meets OCB requirements = OCBL$DeviceNameInput" -ForegroundColor Green -BackgroundColor Black
                ##Read-Host -Prompt "`nWARNING - WARNING - WARNING`n`nComputer will RESTART after you press any key"
                ##Rename-Computer -NewName "OCBL$DeviceNameInput" -Force -Confirm:$false -PassThru -Restart
                # Write-Host "Proceeding with onboarding Intune Autopilot device `n" -ForegroundColor Cyan -BackgroundColor Black
            }
            catch {}
        }
        until ($?)
    }
    return "OCBL$DeviceNameInput"
}



function FunGenerateDeviceName {
    if ($DeviceOfficeLoc -eq 1) {
        $AutopilotDeviceName = $(FunGenHQNaming)
    }
    elseif ($DeviceOfficeLoc -eq "2") {
        $AutopilotDeviceName = "OCB-" + "$(FunGet-CountryISO)" + "$DeviceSerialNumber"
        Write-Host "`n>> Generated computer name: $AutopilotDeviceName"
    }
    return $AutopilotDeviceName
}



##############################################################################################################
# Appearance
##############################################################################################################
function FunDisplayTxtBox {
    param (
        [string[]]$Text  # Accept an array of strings for multiple lines
    )
    # Check if the text is empty or null
    if (-not $Text -or $Text.Count -eq 0) {
        Write-Host "No text provided to display."
        return
    }

    # Trim each line in the input text and remove empty lines
    $Text = $Text | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }

    # If no valid text remains after trimming, display an error message
    if ($Text.Count -eq 0) {
        Write-Host "Text is empty or only whitespace."
        return
    }

    # Find the longest line to calculate box width (add padding)
    $MaxLength = ($Text | Measure-Object -Property Length -Maximum).Maximum
    $BoxWidth = $MaxLength + 4  # Add padding (2 spaces on each side)

    # Ensure the box width is valid and greater than or equal to 6
    if ($BoxWidth -lt 6) {
        $BoxWidth = 6  # Minimum box width for very short text
    }

    # Create the top and bottom borders of the box using || symbols
    $BoxTop = "||" + ("=" * ($BoxWidth - 2)) + "||"
    $BoxBottom = "||" + ("=" * ($BoxWidth - 2)) + "||"

    # Output the top border
    Write-Host $BoxTop

    # Output each line of text, making sure it's padded correctly
    for ($i = 0; $i -lt $Text.Count; $i++) {
        $line = $Text[$i]

        # Calculate how many spaces to add to the right side of the line
        $spacesToAdd = $BoxWidth - $line.Length - 4

        # Ensure that we don't try to add a negative or zero number of spaces
        if ($spacesToAdd -lt 0) {
            $spacesToAdd = 0
        }

        # Create the middle line with text and padding using || symbols
        $BoxMiddle = "||  $line" + (" " * $spacesToAdd) + "||"
        
        # If it's the second line (index 1), set the text color to green
        if ($i -eq 1) {
            Write-Host $BoxMiddle -ForegroundColor Green
        }
        else {
            Write-Host $BoxMiddle
        }
    }

    # Output the bottom border
    Write-Host $BoxBottom
}




function FunGet-DeviceLocation {
    # Set the maximum number of attempts
    $maxAttempts = 3
    $attempts = 0
    $AutopilotDeviceLocation = ""
    # Display options to the user
    Write-Host "`n1- Configure HQ Autopilot Intune device."
    Write-Host "2- Configure Field Autopilot Intune device.`n"
    # Prompt the user to select an option
    # $DeviceLocation = Read-Host "Please select an option (1 or 2)"
    # $selection = Read-Host "Please select an option (1 or 2)"

    # Loop until a valid input is provided or max attempts are reached
    while ($attempts -lt $maxAttempts) {
        # Prompt the user to select an option
        $AutopilotDeviceLocation = Read-Host "Please select an option (1 or 2)"
        
        # If valid input is provided, break out of the loop
        if ($AutopilotDeviceLocation -eq "1" -or $AutopilotDeviceLocation -eq "2") {
            # return $AutopilotDeviceLocation
            break
        }
        
        # If invalid input is provided, show a red bold error message
        Write-Warning "Warning: You should select either 1 for HQ or 2 for Field. Attempts left: $($maxAttempts - ($attempts+1))"

        # Increment the attempt counter
        $attempts++
    }

    # If the user has used all attempts, display a message and exit
    if ($attempts -eq $maxAttempts) {
        Write-Host ">> You have exceeded the maximum number of attempts without vaild choise. Exiting..." -ForegroundColor Red
        exit 1
    }
    return $AutopilotDeviceLocation
}




################################################################################
# Global Parameters
################################################################################
$uri = "https://graph.microsoft.com/v1.0/"
$UriBeta = "https://graph.microsoft.com/beta/"
$OrderTag = "OCB-APPP"

Set-ExecutionPolicy Bypass -Scope Process -Force:$true -Confirm:$false
#Enable TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
################################################################################

$DeviceSerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

FunDisplayTxtBox -Text @(
    "Welcome to Autopilot onboarding",
    "Device Serial: $DeviceSerialNumber",
    "Device Name: $env:computername",
    "Created by x: omar_assaf"
)

# $UserHashChoise = FunGet-HashChoice
$DeviceOfficeLoc = FunGet-DeviceLocation
$DeviceHardwareHash = "$(FunDeviceHashExtract)"
$DeviceGeneratedName = "$(FunGenerateDeviceName)"

FunPreReqInstall
FunConnectGraphforAuth

$OperationStartTime = Get-Date
if ($null -ne $(FunCheckAutopilotDevice)){
    Write-Host ">> Device already exist in Autopilot Intune devices." -ForegroundColor Green
}
else {
    Write-Host "!! Device is not registered in Autopilot, proceeding to register." -ForegroundColor Yellow
    $OperationStartTime = Get-Date
    $AutopilotImportRefId = $(FunImportAutopilotDevice).importId
    while ($($(FunGetAutopilotImportStat).state).deviceImportStatus -eq "unknown" ) {
        Start-Sleep -Seconds 15
        Write-Host ">> Importing device to registeration phase..."        
    }    

    if ($($(FunGetAutopilotImportStat).state).deviceImportStatus -eq "complete") {
        Write-Host ">> Device import had completed successfully.`n"
    }
    else {
        Write-Host ">> Something went wrong, please check with your administrator" -ForegroundColor Red
        FunCleanExit
    }
    FunAutopilotDeviceSync
}

while ($null -eq $(FunCheckAutopilotDevice) ) {
    Start-Sleep -Seconds 10
    Write-Host ">> Checking if device records are avaialble in Intune..."        
}

FunUpdateAutopilotDevice

$TimeToCompleteOperation = Get-Date
$AllowedTimeOperations = New-TimeSpan -Minutes 12
while ($($(FunCheckAutopilotDevice).groupTag) -cne "OCB-APPP" -and $($(FunCheckAutopilotDevice).displayName) -cne "$DeviceGeneratedName") {
    # Check if the time limit has been exceeded
    $TimeToCompleteOperation = Get-Date - $TimeToCompleteOperation
    if ($elapsedTime -gt $AllowedTimeOperations) {
        Write-Host ">> Time limit exceeded 12 minutes" -ForegroundColor Red
        FunCleanExit
    }
    
    Write-Host ">> Updating GroupTag and Computername in Intune..."
    Start-Sleep -Seconds 11
}

Write-Host ">> Good, the device has the proper Group TAG & Name." -ForegroundColor Green
Start-Sleep -Seconds 5
FunGetOperationDuration

if ($env:computername -notlike "$DeviceGeneratedName*") {
    Write-Host "`n>> To complete the process your compter need to restart." -ForegroundColor Yellow
    Read-Host -Prompt "`nWARNING - WARNING - WARNING`nComputer will RESTART after you press any key"
    Rename-Computer -NewName $DeviceGeneratedName -Force -Confirm:$false -PassThru -Restart
}else {
    Write-Host "`n>> Current computer name $DeviceGeneratedName meets requirements" -ForegroundColor Green
}
