$OneDrivePath = "HKLM:Software\Policies\Microsoft\Windows\OneDrive"
$OneDriveValue = Get-ItemPropertyValue -Path $OneDrivePath -Name "DisableFileSyncNGSC" -ErrorAction Continue
If ($OneDriveValue -eq 0){
    Write-Output "Onedrive Sync service is Enabled"
    Exit 0
}
else {
    Write-Host "OndeDrive service is NOT Enabled"
    Exit 1
}
