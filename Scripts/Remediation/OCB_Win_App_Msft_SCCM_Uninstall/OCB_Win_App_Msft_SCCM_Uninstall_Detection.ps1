#Location of 
$CCMFolder = "c:\Windows\ccmsetup"
if (!(Test-Path $CCMFolder)) {
    Write-Output "SCCM client is not installed"
    exit 0
    }
else {
    Write-Output "Warning: SCCM client is found"
    exit 1
    }
# End of detection script
