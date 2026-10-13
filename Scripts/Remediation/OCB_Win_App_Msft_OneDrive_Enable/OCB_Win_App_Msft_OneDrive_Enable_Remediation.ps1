New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -Name OneDrive -ErrorAction Continue
New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value "0" -PropertyType DWord -Force
Write-Output "Created Reg value for Disabling OneDrive usage"
