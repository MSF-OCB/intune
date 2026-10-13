

# Preserve temporary via registery NO WHfB
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft" -Name PassportForWork -ErrorAction Continue
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork" -Name "Enabled" -Value "0" -PropertyType DWord -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork" -Name "DisablePostLogonProvisioning" -Value "1" -PropertyType DWord -Force


