##################################################################
#   _______     ______  ______ _____            _____ _  _________ ______ _____ _    _ 
#  / ____\ \   / /  _ \|  ____|  __ \     /\   / ____| |/ /__   __|  ____/ ____| |  | |
# | |     \ \_/ /| |_) | |__  | |__) |   /  \ | |    | ' /   | |  | |__ | |    | |__| |
# | |      \   / |  _ <|  __| |  _  /   / /\ \| |    |  <    | |  |  __|| |    |  __  |
# | |____   | |  | |_) | |____| | \ \  / ____ \ |____| . \ _ | |  | |___| |____| |  | |
#  \_____|  |_|  |____/|______|_|  \_\/_/    \_\_____|_|\_(_)|_|  |______\_____|_|  |_|
#
##################################################################
# Authored by: Omar Assaf
# X: omar_assaf
# Please credit the author if you use this script
##################################################################

<#
.SYNOPSIS
    Autodesk Inventory Tool (AIT) Report Upload.

.DESCRIPTION
    This script will upload the AIT report to the specified Azure Blob Storage.

.EXAMPLE
    Just run the script.

.NOTES
    Author: Omar Assaf
    lastUpdated: Aug-2025
    Version: 3.14
    Disclaimer: This script is provided 'as is' without any warranty. The author is not liable for any damages or issues that arise from using this script. Use at your own risk.

.LINK
    https://samtools.autodesk.com/m/104297/l/1403329-introduction
#>

##################################################################
# --- Start Transcript Logging ---
function Get-TimeStamp {
    return Get-Date -Format "dd-MM-yyyy_HH:mm:ss.fff"
}
$logPath = "C:\ProgramData\MSF\Logs\Intune\Apps"
$logFile = "$logPath\Autodesk_Inventory_Upload.log"

if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $logFile -Force -Append
#Region Report generation
###################################################################
#Region Variable Declaration for Autodesk Inventory Tool (AIT) Report
$CompanyName = "MSFOCB"
$aitpath = "C:\Program Files (x86)\Autodesk\Autodesk Inventory Tool\AIT.exe"
$DeviceSerial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
$computername = $env:COMPUTERNAME
$dataStorePath = "C:\ProgramData\Autodesk\AIT\DataStore.xml"
$targetPath = "C:\ProgramData\Autodesk\AIT\Autodesk-$DeviceSerial.xml" # Path to the local file
#EndRegion Variable Declaration
###################################################################
# Clear previous report if exists
if (Test-Path $dataStorePath) {
    Write-Output "$(Get-TimeStamp) >>Previous DataStore.xml found, deleting it."
    Remove-Item -Path $dataStorePath -Force -Confirm:$false
    Start-Sleep -Seconds 5
}
# Validate if inventory tool is installed
if (Test-Path $aitpath) {
    Write-Output "$(Get-TimeStamp) >>Autodesk Inventory Tool (AIT) is installed."
    # If the target file exists, we assume the report is ready for upload
    if (-not (Test-Path $targetPath)) {
        Write-Output "$(Get-TimeStamp) >>Error: $DeviceSerial.xml report not found, proceeding to run Autodesk Inventory Tool."
        # Run the Autodesk Inventory Tool
        Start-Process -FilePath $aitpath -ArgumentList "/c $computername /fp /lu /rp /sl" -WindowStyle Hidden -Wait
        Start-Sleep -Seconds 10
    }
    else {
        Write-Output "$(Get-TimeStamp) >>DataStore.xml already exists"
    }
    # Check if $DeviceSerial.xml exists
    if (-not (Test-Path $targetPath)) {
        Write-Output "$(Get-TimeStamp) >>Report for $DeviceSerial doesnt exist!, proceeding to rename DataStore.xml."
        # Perform the copy&rename operation
        try {
            Copy-Item -Path $dataStorePath -Destination $targetPath -ErrorAction Stop
            start-sleep -Seconds 5
            Write-Output "$(Get-TimeStamp) >>Successfully renamed DataStore.xml to $targetPath."
        }
        catch {
            Write-Output "$(Get-TimeStamp) >>Error renaming file: $_"
            Stop-Transcript | Out-Null
            exit 1
        }
    }
    else {
        Write-Output "$(Get-TimeStamp) >>Report for $computername already exists, proceeding to upload it."
    }
}
else {
    Write-Output "$(Get-TimeStamp) >>Autodesk Inventory Tool (AIT) is not installed."
    Stop-Transcript | Out-Null
    exit 1
}
#EndRegion Report generation
#
#Region Report Upload
###################################################################
## Define variables for uploading Report
$storageAccountName = "msfocbshare"  # Storage account name
$containerName = "ict-sd/autodesk"   # Container name
$sasToken = "?sv=2024-11-04&ss=b&srt=co&sp=rwdltfx&se=2026-01-01T19:25:06Z&st=2025-08-06T10:10:06Z&spr=https&sig=UD1%2FuDS3BWnMhZGbgYZXYZG4mD6QIVuHkq1ES7QhX2M%3D"  # Provided SAS token
$blobName = "Autodesk-$DeviceSerial.xml"  # Blob name in the container

# Validate local report file exists
if (-not (Test-Path $targetPath)) {
    Write-Output "$(Get-TimeStamp) >>Local file '$targetPath' does not exist, Please run the AIT scanner."
    Stop-Transcript | Out-Null
    exit 1
}
else {
    Write-Output "$(Get-TimeStamp) >>Checking if $blobName is available at Azure Blob..."

    $currentFileUrl = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"

    try {
        Invoke-WebRequest -Uri $currentFileUrl -UseBasicParsing -ErrorAction stop > $null
        Write-Output "$(Get-TimeStamp) >>Blob $blobName already exists in container: $containerName."
    }
    catch {
        Write-Output "$(Get-TimeStamp) >>$blobName does not exists, proceeding to upload it..."

        try {
        
            # Get file content and size
            $fileContent = [System.IO.File]::ReadAllBytes($targetPath)
            $fileSize = $fileContent.Length

            # Construct and validate the REST API URL
            $blobUrl = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName$sasToken"

            # Set headers for the PUT request
            $headers = @{
                "x-ms-date"      = (Get-Date -Format "R")  # RFC 1123 date format (e.g., Thu, 07 Aug 2025 11:14:00 GMT)
                "x-ms-version"   = "2024-11-04"           # Match SAS token API version
                "x-ms-blob-type" = "BlockBlob"            # Specify BlockBlob type
                "Content-Length" = $fileSize
                "Content-Type"   = "application/xml"       # Set to application/xml for .xml file
            }

            # Log request details for debugging
            Write-Output "$(Get-TimeStamp) >>Uploading $targetPath..."
            Write-Output "$(Get-TimeStamp) >>Destination Blob: $containerName/$blobName"
            #Write-Output "$(Get-TimeStamp) >>Request Headers: $($headers | ConvertTo-Json -Depth 2)"

            # Upload the file as a BlockBlob and capture response details
            $response = Invoke-WebRequest -Uri $blobUrl -Method Put -Headers $headers -Body $fileContent -UseBasicParsing -ContentType "application/xml" -ErrorAction Stop

            # Log response details
            Write-Output "$(Get-TimeStamp) >>File uploaded successfully to: https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"
            Write-Output "$(Get-TimeStamp) >>HTTP Status Code: $($response.StatusCode) ($($response.StatusDescription))"
            if ($response.StatusCode -eq 201) {
                $Key = "HKEY_LOCAL_MACHINE\Software\$CompanyName\Autodesk\Inventory"
                $NOW = Get-Date -Format "yyyyMMdd-hhmmss.fff"
                [microsoft.win32.registry]::SetValue($Key, "Uploaded", $NOW)
            }
        }
        catch {
            Write-Error "Upload failed: $($_.Exception.Message)"
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode
                $statusDescription = $_.Exception.Response.StatusDescription
                $responseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($responseStream)
                $responseBody = $reader.ReadToEnd()
                Write-Error "HTTP Status: $statusCode - $statusDescription"
                Write-Error "Response Body: $responseBody"
            }
        }
    }
}
#EndRegion Report Upload
Write-Output "$(Get-TimeStamp) >>Script execution completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
Stop-Transcript | Out-Null
