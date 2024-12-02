@echo off
:: Use this script to fetch new PPKG
IF NOT EXIST "c:\Temp" (
    mkdir "c:\Temp"
)
powershell.exe Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Webrequest 'https://raw.githubusercontent.com/MSF-OCB/intune/refs/heads/main/Scripts/Enrollment/PPKG/PPKG_Fetch.ps1' -OutFile C:\Temp\PPKG_Fetch.ps1; C:\Temp\PPKG_Fetch.ps1
