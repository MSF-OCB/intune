New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -Name OneDrive -ErrorAction Continue
New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value "1" -PropertyType DWord -Force
