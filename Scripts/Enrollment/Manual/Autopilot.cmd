@echo off
:: Script to register devices to autopilot manually

:: Check if device can ping the internet (1.1.1.1 is used here as a placeholder)
ping -n 2 -w 700 1.1.1.1 | find "TTL=" > NUL
IF %ERRORLEVEL% EQU 0 (
    :: Check if folder C:\Windows\MSF exists, create if not
    IF NOT EXIST "C:\Windows\MSF" (
        mkdir "C:\Windows\MSF"
    )
    
    :: Print success message (green text)
    echo [92m^Device is connected to the internet.^[0m

    :: Download the PowerShell script and check if it's downloaded correctly
    powershell.exe Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-WebRequest 'https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Enroll/Manual/Autopilot_Register_hash.ps1' -OutFile 'C:\Windows\MSF\Autopilot_Register_hash.ps1'; "C:\Windows\MSF\Autopilot_Register_hash.ps1"

) ELSE (
    :: Print failure message (red text)
    echo [91m^WARNING!!! Your device is offline, Please troubleshoot your connectivity.^[0m
)
