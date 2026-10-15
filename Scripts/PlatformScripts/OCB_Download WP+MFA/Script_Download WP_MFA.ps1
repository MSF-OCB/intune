# Fetch files from Azure CDN+FrontDoor to local directory
$Webfile = "https://msfocbshare.z6.web.core.windows.net/data/links.txt"
$Name = "C:\Temp\urlfiles.csv"
Invoke-WebRequest -URI $Webfile -OutFile $Name
$CSV = Import-Csv "C:\Temp\urlfiles.csv" -Delimiter ","
ForEach ($row in $CSV) 
{
$Address = $row.URL
$Folder = $row.Destination
Invoke-WebRequest -Uri $Address -OutFile $Folder
}
Remove-Item -Path "C:\Temp\urlfiles.csv" -Force > $null
## End of pushing web components
