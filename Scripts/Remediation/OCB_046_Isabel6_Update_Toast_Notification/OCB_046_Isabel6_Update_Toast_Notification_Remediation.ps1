## ==========================================================================
## MSFOCB Script
## --------------------------------------------------------------------------
## Filename   : Toast_Notification_v14.ps1
## Version         : 14.0
## Creation Date   : 01-08-2025
## Last Update     : 23-09-2025
## --------------------------------------------------------------------------
## Script's Author    : Fabrizio.Murgia@brussels.msf.org
## --------------------------------------------------------------------------
## Description :
## Create a Toast Notification for a specific app: Remediation script must run under user context
## --------------------------------------------------------------------------
## Sources :
## https://4sysops.com/archives/generate-windows-toast-notifications-with-the-powershell-module-burnttoast/
## https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/toast-notifications-overview
## https://den.dev/blog/powershell-windows-notification/
## https://www.imab.dk/windows-10-toast-notification-script/
## ==========================================================================

#### -==- MAIN -==- ####

# Set up PowerShell parameters
Set-PSDebug -Trace 0    # 0 - 1 - 2
Set-StrictMode -Version 3

# Retrive the path from where the script has been run and put it in the $MyPath variable
$MyPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$_ALLUSERSPROFILE = ${Env:ALLUSERSPROFILE}

## ::::::::::::::::::::::::::::::::::::::

<#
        .SYNOPSIS
        it Creates and displays a Toast Notification 
         
        .DESCRIPTION
        - Create a Remediation log file
        - Check if Nuget is installed
        - Create a Toas Notification
#>

# Create log directory and file
$LogPath = "C:\ProgramData\MSF\Logs\"
$LogFile = Join-Path $LogPath "Remediation_for_Isabel6.log"
if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $LogFile -Append

function Log {
    param([string]$Message)
    Write-Output $Message
}

function Ensure_NuGetProvider {
    Log "Checking for NuGet provider..."
    $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nugetProvider) {
        Log "NuGet provider not found. Installing..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
            Install-PackageProvider -Name NuGet -Force -ForceBootstrap -Scope CurrentUser -Confirm:$false | Out-Null
            Import-PackageProvider -Name NuGet -Force | Out-Null

            $repo = Get-PSRepository -Name PSGallery
            if ($repo.InstallationPolicy -ne 'Trusted') {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            }

            Log "NuGet provider installed and PSGallery trusted."
        }
        catch {
            Log "Error installing NuGet provider: $_"
        }
    }
    else {
        Log "NuGet provider is already installed."
    }
}

function Ensure_BurntToast {
    Log "Checking for BurntToast module..."
    try {
        if (-not (Get-Module -ListAvailable -Name BurntToast)) {
            Install-Module -Name BurntToast -Force -Scope CurrentUser -ErrorAction Stop
        }
        Import-Module BurntToast -ErrorAction Stop
        Log "BurntToast module is ready."
        return $true
    }
    catch {
        Log "Error ensuring BurntToast module: $_"
        return $false
    }
}

function Show_Toast {
    param (
        [string]$AppName,
        [string]$AppLink,
        [string]$HeroImage,
        [string]$AppLogo,
        [string]$Title,
        [string]$Message
    )

    try {
        # Clear previous notification with same identifier
        Clear-BurntToastNotification -UniqueIdentifier "$AppName Update" -ErrorAction SilentlyContinue
        $existingToast = Get-BurntToastNotification -UniqueIdentifier "$AppName Update" -ErrorAction SilentlyContinue
        if ($existingToast) {
            Write-Output "Notification with UniqueIdentifier '$AppName Update' still exists."
        }
        else {
            Write-Output "Notification cache cleared successfully."
        }

        # Create and show the toast
        $Action = New-BTButton -Content "Open Company Portal" -Arguments $AppLink -ActivationType Protocol
        New-BurntToastNotification -Text $Title, $Message -AppLogo $AppLogo -HeroImage $HeroImage -Button $Action -UniqueIdentifier "$AppName Update"

        $Action = New-BTButton -Content "Open Company Portal" -Arguments $AppLink -ActivationType Protocol
        New-BurntToastNotification -Text $Title, $Message -AppLogo $AppLogo -HeroImage $HeroImage -Button $Action -UniqueIdentifier "$AppName Update"
        Log "Toast notification displayed successfully."
        return $true
    }
    catch {
        Log "Error displaying toast notification: $_"
        return $false
    }
}

# Main Execution
Ensure_NuGetProvider

if (Ensure_BurntToast) {
    $AppName = "Isabel 6"
    $AppLink = "companyportal:ApplicationId=1530a761-2cef-4785-b728-9628e709809f"
    $HeroImage = "https://msfocbshare.blob.core.windows.net/ict-sd/docs/Toast_Notification_pictures/MSF_banner.png"
    $AppLogo = "https://msfocbshare.blob.core.windows.net/ict-sd/docs/Toast_Notification_pictures/CompanyPortal_logo.png"
    $Title = "$AppName Update Available!"
    $Message = "Your version of $AppName is outdated. Please update it via Company Portal."

    if (Show_Toast -AppName $AppName -AppLink $AppLink -HeroImage $HeroImage -AppLogo $AppLogo -Title $Title -Message $Message) {
        Log "Remediation completed successfully."
        Stop-Transcript
        exit 0
    }
    else {
        Log "Remediation failed during toast notification."
        Stop-Transcript
        exit 1  
    }
}
else {
    Log "Remediation failed during BurntToast setup."
    Stop-Transcript
    exit 1  
}

# EOF #
# SIG # Begin signature block
# MIIb3QYJKoZIhvcNAQcCoIIbzjCCG8oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUOXsB9lV88RV3JV9yQjpMVAo7
# xUqgghZKMIIDDDCCAfSgAwIBAgIQW28BeDvOrYlCBffDgpBxGjANBgkqhkiG9w0B
# AQsFADAeMRwwGgYDVQQDDBNJbnR1bmVTY3JpcHRDZXJ0LVY1MB4XDTI1MDkyOTA5
# MTU1M1oXDTQ1MDkyOTA5MjU1M1owHjEcMBoGA1UEAwwTSW50dW5lU2NyaXB0Q2Vy
# dC1WNTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOXy4M3OrZHkV/UT
# WkO45270JOc6xeja3yjnc4MHh8iFc7lRF8EsxZ8lxj5mlf25QOD9U83P6BIuUEKI
# SNtAG2kI4dLX2ImgpEROpQIW5ga8umYWoE+TXUSA5FEp0gypPGQeXaWARxjB2Iuj
# MXigIdMUCXR6QrD436Jy74JJ6Ogfh9dOcsnv17iVR1FjiTwbtBLvVSdIvjJI0IIe
# wC3pR/gsWhD2gYygrF0Ywh/liQFXvIIQSbpr+/0d6KFuaTHb5IUyo2VHzUx5ka+U
# GFIRwl0CiSjetBmJaDC7MSV24H8vScIOOrspWREO422HoWINPaPZUhzGucfTGrhP
# L8UoeAkCAwEAAaNGMEQwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUF
# BwMDMB0GA1UdDgQWBBSDC2sfNqB3jJDz4PE7fWch1p25KzANBgkqhkiG9w0BAQsF
# AAOCAQEANIK8LLLBD6nAbjaA4pJEArl4vOdEdn4oi7Pk3IoqRNDylCS+5gM+TUip
# 8k2iMJrzKNgkTRxmfOFi+H4IRUtOkJ078dxIlY4Xb1VugAtbLwjRaSKKvZvcpKxK
# EgRKTxCVFVlkcm1zqrR7ykP3Wj4z+YM2WMABbBB2vj5x3Ngs0+NadK8OEYhr3awP
# xp8HK3ExPKtE3HogYhXWzqI1D0xMAVtL+hdECYIzBxVXoiP+Ifg1Sgf5J3V9xgRU
# AhfYTW74xExjqDwUd35q7ggEAC2v/xmQUoclinvm2M/Inhqm8W9SBXoc/9lLSJ2e
# eoj+1u7Apxcd2yW8eoxxWYltZENoTjCCBY0wggR1oAMCAQICEA6bGI750C3n79tQ
# 4ghAGFowDQYJKoZIhvcNAQEMBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMb
# RGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTIyMDgwMTAwMDAwMFoXDTMx
# MTEwOTIzNTk1OVowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQg
# VHJ1c3RlZCBSb290IEc0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# v+aQc2jeu+RdSjwwIjBpM+zCpyUuySE98orYWcLhKac9WKt2ms2uexuEDcQwH/Mb
# pDgW61bGl20dq7J58soR0uRf1gU8Ug9SH8aeFaV+vp+pVxZZVXKvaJNwwrK6dZlq
# czKU0RBEEC7fgvMHhOZ0O21x4i0MG+4g1ckgHWMpLc7sXk7Ik/ghYZs06wXGXuxb
# Grzryc/NrDRAX7F6Zu53yEioZldXn1RYjgwrt0+nMNlW7sp7XeOtyU9e5TXnMcva
# k17cjo+A2raRmECQecN4x7axxLVqGDgDEI3Y1DekLgV9iPWCPhCRcKtVgkEy19sE
# cypukQF8IUzUvK4bA3VdeGbZOjFEmjNAvwjXWkmkwuapoGfdpCe8oU85tRFYF/ck
# XEaPZPfBaYh2mHY9WV1CdoeJl2l6SPDgohIbZpp0yt5LHucOY67m1O+SkjqePdwA
# 5EUlibaaRBkrfsCUtNJhbesz2cXfSwQAzH0clcOP9yGyshG3u3/y1YxwLEFgqrFj
# GESVGnZifvaAsPvoZKYz0YkH4b235kOkGLimdwHhD5QMIR2yVCkliWzlDlJRR3S+
# Jqy2QXXeeqxfjT/JvNNBERJb5RBQ6zHFynIWIgnffEx1P2PsIV/EIFFrb7GrhotP
# wtZFX50g/KEexcCPorF+CiaZ9eRpL5gdLfXZqbId5RsCAwEAAaOCATowggE2MA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFOzX44LScV1kTN8uZz/nupiuHA9PMB8G
# A1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA4GA1UdDwEB/wQEAwIBhjB5
# BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0
# LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRw
# Oi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3Js
# MBEGA1UdIAQKMAgwBgYEVR0gADANBgkqhkiG9w0BAQwFAAOCAQEAcKC/Q1xV5zhf
# oKN0Gz22Ftf3v1cHvZqsoYcs7IVeqRq7IviHGmlUIu2kiHdtvRoU9BNKei8ttzjv
# 9P+Aufih9/Jy3iS8UgPITtAq3votVs/59PesMHqai7Je1M/RQ0SbQyHrlnKhSLSZ
# y51PpwYDE3cnRNTnf+hZqPC/Lwum6fI0POz3A8eHqNJMQBk1RmppVLC4oVaO7KTV
# Peix3P0c2PR3WlxUjG/voVA9/HYJaISfb8rbII01YBwCA8sgsKxYoA5AY8WYIsGy
# WfVVa88nq2x2zm8jLfR+cWojayL/ErhULSd+2DrZ8LaHlv1b0VysGMNNn3O3Aamf
# V6peKOK5lDCCBrQwggScoAMCAQICEA3HrFcF/yGZLkBDIgw6SYYwDQYJKoZIhvcN
# AQELBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3Rl
# ZCBSb290IEc0MB4XDTI1MDUwNzAwMDAwMFoXDTM4MDExNDIzNTk1OVowaTELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdp
# Q2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1
# IENBMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALR4MdMKmEFyvjxG
# wBysddujRmh0tFEXnU2tjQ2UtZmWgyxU7UNqEY81FzJsQqr5G7A6c+Gh/qm8Xi4a
# PCOo2N8S9SLrC6Kbltqn7SWCWgzbNfiR+2fkHUiljNOqnIVD/gG3SYDEAd4dg2dD
# GpeZGKe+42DFUF0mR/vtLa4+gKPsYfwEu7EEbkC9+0F2w4QJLVSTEG8yAR2CQWIM
# 1iI5PHg62IVwxKSpO0XaF9DPfNBKS7Zazch8NF5vp7eaZ2CVNxpqumzTCNSOxm+S
# AWSuIr21Qomb+zzQWKhxKTVVgtmUPAW35xUUFREmDrMxSNlr/NsJyUXzdtFUUt4a
# S4CEeIY8y9IaaGBpPNXKFifinT7zL2gdFpBP9qh8SdLnEut/GcalNeJQ55IuwnKC
# gs+nrpuQNfVmUB5KlCX3ZA4x5HHKS+rqBvKWxdCyQEEGcbLe1b8Aw4wJkhU1JrPs
# FfxW1gaou30yZ46t4Y9F20HHfIY4/6vHespYMQmUiote8ladjS/nJ0+k6Mvqzfpz
# PDOy5y6gqztiT96Fv/9bH7mQyogxG9QEPHrPV6/7umw052AkyiLA6tQbZl1KhBtT
# asySkuJDpsZGKdlsjg4u70EwgWbVRSX1Wd4+zoFpp4Ra+MlKM2baoD6x0VR4RjSp
# WM8o5a6D8bpfm4CLKczsG7ZrIGNTAgMBAAGjggFdMIIBWTASBgNVHRMBAf8ECDAG
# AQH/AgEAMB0GA1UdDgQWBBTvb1NK6eQGfHrK4pBW9i/USezLTjAfBgNVHSMEGDAW
# gBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAww
# CgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhhodHRwOi8v
# b2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNlcnRzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3J0MEMGA1UdHwQ8MDow
# OKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRS
# b290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkq
# hkiG9w0BAQsFAAOCAgEAF877FoAc/gc9EXZxML2+C8i1NKZ/zdCHxYgaMH9Pw5tc
# BnPw6O6FTGNpoV2V4wzSUGvI9NAzaoQk97frPBtIj+ZLzdp+yXdhOP4hCFATuNT+
# ReOPK0mCefSG+tXqGpYZ3essBS3q8nL2UwM+NMvEuBd/2vmdYxDCvwzJv2sRUoKE
# fJ+nN57mQfQXwcAEGCvRR2qKtntujB71WPYAgwPyWLKu6RnaID/B0ba2H3LUiwDR
# AXx1Neq9ydOal95CHfmTnM4I+ZI2rVQfjXQA1WSjjf4J2a7jLzWGNqNX+DF0SQzH
# U0pTi4dBwp9nEC8EAqoxW6q17r0z0noDjs6+BFo+z7bKSBwZXTRNivYuve3L2oiK
# NqetRHdqfMTCW/NmKLJ9M+MtucVGyOxiDf06VXxyKkOirv6o02OoXN4bFzK0vlNM
# svhlqgF2puE6FndlENSmE+9JGYxOGLS/D284NHNboDGcmWXfwXRy4kbu4QFhOm0x
# JuF2EZAOk5eCkhSxZON3rGlHqhpB/8MluDezooIs8CVnrpHMiD2wL40mm53+/j7t
# FaxYKIqL0Q4ssd8xHZnIn/7GELH3IdvG2XlM9q7WP/UwgOkw/HQtyRN62JK4S1C8
# uw3PdBunvAZapsiI5YKdvlarEvf8EA+8hcpSM9LHJmyrxaFtoza2zNaQ9k+5t1ww
# ggbtMIIE1aADAgECAhAKgO8YS43xBYLRxHanlXRoMA0GCSqGSIb3DQEBCwUAMGkx
# CzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4
# RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYg
# MjAyNSBDQTEwHhcNMjUwNjA0MDAwMDAwWhcNMzYwOTAzMjM1OTU5WjBjMQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lD
# ZXJ0IFNIQTI1NiBSU0E0MDk2IFRpbWVzdGFtcCBSZXNwb25kZXIgMjAyNSAxMIIC
# IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0EasLRLGntDqrmBWsytXum9R
# /4ZwCgHfyjfMGUIwYzKomd8U1nH7C8Dr0cVMF3BsfAFI54um8+dnxk36+jx0Tb+k
# +87H9WPxNyFPJIDZHhAqlUPt281mHrBbZHqRK71Em3/hCGC5KyyneqiZ7syvFXJ9
# A72wzHpkBaMUNg7MOLxI6E9RaUueHTQKWXymOtRwJXcrcTTPPT2V1D/+cFllESvi
# H8YjoPFvZSjKs3SKO1QNUdFd2adw44wDcKgH+JRJE5Qg0NP3yiSyi5MxgU6cehGH
# r7zou1znOM8odbkqoK+lJ25LCHBSai25CFyD23DZgPfDrJJJK77epTwMP6eKA0kW
# a3osAe8fcpK40uhktzUd/Yk0xUvhDU6lvJukx7jphx40DQt82yepyekl4i0r8OEp
# s/FNO4ahfvAk12hE5FVs9HVVWcO5J4dVmVzix4A77p3awLbr89A90/nWGjXMGn7F
# QhmSlIUDy9Z2hSgctaepZTd0ILIUbWuhKuAeNIeWrzHKYueMJtItnj2Q+aTyLLKL
# M0MheP/9w6CtjuuVHJOVoIJ/DtpJRE7Ce7vMRHoRon4CWIvuiNN1Lk9Y+xZ66laz
# s2kKFSTnnkrT3pXWETTJkhd76CIDBbTRofOsNyEhzZtCGmnQigpFHti58CSmvEyJ
# cAlDVcKacJ+A9/z7eacCAwEAAaOCAZUwggGRMAwGA1UdEwEB/wQCMAAwHQYDVR0O
# BBYEFOQ7/PIx7f391/ORcWMZUEPPYYzoMB8GA1UdIwQYMBaAFO9vU0rp5AZ8esri
# kFb2L9RJ7MtOMA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUBAf8EDDAKBggrBgEFBQcD
# CDCBlQYIKwYBBQUHAQEEgYgwgYUwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRp
# Z2ljZXJ0LmNvbTBdBggrBgEFBQcwAoZRaHR0cDovL2NhY2VydHMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIw
# MjVDQTEuY3J0MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYy
# MDI1Q0ExLmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJ
# KoZIhvcNAQELBQADggIBAGUqrfEcJwS5rmBB7NEIRJ5jQHIh+OT2Ik/bNYulCrVv
# hREafBYF0RkP2AGr181o2YWPoSHz9iZEN/FPsLSTwVQWo2H62yGBvg7ouCODwrx6
# ULj6hYKqdT8wv2UV+Kbz/3ImZlJ7YXwBD9R0oU62PtgxOao872bOySCILdBghQ/Z
# LcdC8cbUUO75ZSpbh1oipOhcUT8lD8QAGB9lctZTTOJM3pHfKBAEcxQFoHlt2s9s
# XoxFizTeHihsQyfFg5fxUFEp7W42fNBVN4ueLaceRf9Cq9ec1v5iQMWTFQa0xNqI
# tH3CPFTG7aEQJmmrJTV3Qhtfparz+BW60OiMEgV5GWoBy4RVPRwqxv7Mk0Sy4QHs
# 7v9y69NBqycz0BZwhB9WOfOu/CIJnzkQTwtSSpGGhLdjnQ4eBpjtP+XB3pQCtv4E
# 5UCSDag6+iX8MmB10nfldPF9SVD7weCC3yXZi/uuhqdwkgVxuiMFzGVFwYbQsiGn
# oa9F5AaAyBjFBtXVLcKtapnMG3VH3EmAp/jsJ3FVF3+d1SVDTmjFjLbNFZUWMXuZ
# yvgLfgyPehwJVxwC+UpX2MSey2ueIu9THFVkT+um1vshETaWyQo8gmBto/m3acaP
# 9QsuLj3FNwFlTxq25+T4QwX9xa6ILs84ZPvmpovq90K8eWyG2N01c4IhSOxqt81n
# MYIE/TCCBPkCAQEwMjAeMRwwGgYDVQQDDBNJbnR1bmVTY3JpcHRDZXJ0LVY1AhBb
# bwF4O86tiUIF98OCkHEaMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKAC
# gAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsx
# DjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBSft1IlJhbwQOJMvDt14b5M
# Ox70MDANBgkqhkiG9w0BAQEFAASCAQCP5tzX68hQ4s6f2eCq54lMnQn0ypMM3Oxk
# SRTo9nLbD644a+1hsrBIkYaIGUgcMfPLbPc6MEkLT2hE7EDFjN+fLgC7Vkkqv+EJ
# D+1A8fKLG+hSPM1vqBuLwRjjbDj8BUtQlNT43Yvl5K3SQbIvBjNe7Ty4jKXA8WGd
# Wr0ESmMcHiN73fZ+mctKZc40mnV6YjJUsx4r15XJIESeQyIJ1/K8tDcvYa+y2Nm1
# 2jejWZqRs6A1OQ4FWvY2ErRK8P50SJVYbtEfzDZ7Yovy5sC7v9KNp2iW+qKT6oUj
# m7cuVgkiof9HOjVQEL9+NUrLYy5JOqftl0ipNP1T06tqCrFH20p+oYIDJjCCAyIG
# CSqGSIb3DQEJBjGCAxMwggMPAgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNVBAoT
# DkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRp
# bWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMQIQCoDvGEuN8QWC0cR2
# p5V0aDANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEw
# HAYJKoZIhvcNAQkFMQ8XDTI1MDkyOTA5MjU1MFowLwYJKoZIhvcNAQkEMSIEIBRs
# gzQlZOFYHLcCxlzmqIXfD/kNiQzVRd855/lAx0oZMA0GCSqGSIb3DQEBAQUABIIC
# AKAUixZ3+nmI8v+GxEfjhC9R/4txM8QW0waj/1ma4sopEMYTSOqgm94nmfwwN9UU
# dd/NqEJv+JeW3ckIGqAMbkwcDAt+XUDQE7L+owGnjyDcytLp/h5EcMnMDBHLLER1
# s/gckQS8vvPKs/CCt+2MBaRk84Cu6d76a8bfUvlSkOZdufdyrgV31aGfCI7mFmNi
# +aEcLDk5fvocztGwSCm9SRyzM1DPxlzxAxTAXqpP2m5gK1OVc87Ew9OKky4F6CAF
# kJCArbS7u43TImuyODJRGGGv1kXfOQFEy04T+/9wMrr46ikcLkRtiU48Wbu51e93
# fuMUz0coIIRMDvQPMZhSDLLJmAz4jFajl0UEpKrvc08bk7qyZzhnTsaleNouUoKX
# PqhtjqqAwmGnLsF4NQGV4QTbgJnPXdZsaN6ztPKKYeeeGpk46gq4adzajoui1a1D
# FsDySLHl7FIxnlD77wk+kouDe7U69f1hiuk2fJP/bgxm84h0pTwAEInhWI7xAeEa
# 0+/nagVo0X5NYs0l0XYPQVbKSYSz3oaZpq6dY/T94MSPRoqIn4G98we3RfRj1g33
# ajmB6UlgOZlsjpvRHfE5Ek4fg30p/FLU9Lw0KRGO3KU7mUeuVfBdiwv4hycoTuvo
# lnOltQrtyXwGYEW29RkxSX6UhtYlv6q6NIwe9DAhwV0/
# SIG # End signature block

