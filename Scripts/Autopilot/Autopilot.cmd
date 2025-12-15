@echo off
:: Script to register devices to autopilot manually
:: Created by X: omar_assaf

:: Check internet connectivity
ping -n 2 -w 700 1.1.1.1 | find "TTL=" > NUL
IF %ERRORLEVEL% EQU 0 (
    echo [92m^Device is connected to the internet. Running Autopilot registration...^[0m
    
    :: Download and execute PowerShell script directly
    powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Invoke-Expression ([System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -Uri 'https://msfocbshare.blob.core.windows.net/ict-prod/Intune/Enroll/Manual/Autopilot_Register_hash.ps1' -UseBasicParsing).Content))"
    
) ELSE (
    echo [91m^WARNING!!! Your device is offline, Please troubleshoot your connectivity.^[0m
)
