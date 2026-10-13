# Fetch files from Azure CDN+FrontDoor to local directory
# TLS 1.2 must be used to communicate via https
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Webfile = "https://msfocbshare.z6.web.core.windows.net/data/links.txt"
$CSV = Invoke-RestMethod -URI $Webfile -UseBasicParsing | ConvertFrom-Csv
ForEach ($row in $CSV) 
{
$Address = $row.URL
$Folder = $row.Destination
Invoke-RestMethod -Method Get -Uri $Address -OutFile $Folder -UseBasicParsing
}
