# Start transcript for logging
$LogPath = "C:\ProgramData\MSF\Logs\NestorShortcutRemediation.log"
Start-Transcript -Path $LogPath -Append

# Function to create shortcut
function CreateShortcut {
    param (
        [string]$ShortcutPath,
        [string]$TargetPath
    )
    Write-Host "Creating shortcut..."
    $WShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetPath
    $Shortcut.IconLocation = "C:\windows\system32\imageres.dll,33"
    $Shortcut.Save()
    Write-Host "Shortcut created successfully"
}

try {
    Write-Host "Starting shortcut remediation script"

    # Define parameters
    $ShortcutName = "Nestor"
    $TargetPath = "\\Nestor"
    $ShortcutPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("CommonDesktopDirectory"), "$ShortcutName.lnk")

    Write-Host "Checking if shortcut already exists at: $ShortcutPath"

    # Check if the shortcut already exists
    if (Test-Path $ShortcutPath) {
        Write-Host "Shortcut already exists. No action taken."
        exit 0  # Exit with success code
    }

    # Create the shortcut by calling the Create-Shortcut function
    CreateShortcut -ShortcutPath $ShortcutPath -TargetPath $TargetPath

    # Output success message
    Write-Host "Shortcut created successfully at: $ShortcutPath"
    exit 0  # Exit with success code
} catch {
    # Catch any unexpected errors and output them
    Write-Error "An error occurred during remediation: $_"
    exit 1  # Exit with error code
} finally {
    Stop-Transcript
}