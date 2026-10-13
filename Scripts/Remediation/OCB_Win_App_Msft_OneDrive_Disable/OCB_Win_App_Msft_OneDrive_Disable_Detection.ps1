$OneDrivePath = "HKLM:Software\Policies\Microsoft\Windows\OneDrive"
$OneDriveValue = Get-ItemPropertyValue -Path $OneDrivePath -Name "DisableFileSyncNGSC" -ErrorAction Continue
If ($OneDriveValue -eq 1){
    Write-Output "Onedrive Sync service is disabled"
    Exit 0
}
else {
    Write-Host "OndeDrive service is NOT configured properly"
    Exit 1
}
