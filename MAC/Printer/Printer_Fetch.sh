#!/bin/bash
#set -x
############################################################################################
##
## Script to fetch requirements to perform mapping for shared printers from Print Server
##
############################################################################################

## Created by X: omar_assaf
## 

# Define the printer details
logdir="/Library/Logs/MSF/IntuneScripts/Printers"                         # Directory for logs
log="$logdir/PrinterDownload.log"                                         # The location of the script log file

function startLog() {

    ###################################################
    ###################################################
    ##
    ##  start logging - Output to log file and STDOUT
    ##
    ####################
    ####################

    if [[ ! -d "$logdir" ]]; then
        ## Creating Metadirectory
        echo "$(date) | Creating [$logdir] to store logs"
        mkdir -p "$logdir"
    fi

    exec &> >(tee -a "$log")
    
}

# Initiate logging
startLog

echo ""
echo "###################################################################################################################"
echo "# $(date) | Logging Printer fetching to [$log]"
echo "###################################################################################################################"
echo ""

# URL of the printer mapping tool
printmap="https://raw.githubusercontent.com/MSF-OCB/intune/main/MAC/printer_map.sh"
# Destination directory printer mapping tool
mkdir -p "/Library/MSF/Printer"
# Download printer mapping tool
curl -o "/Library/MSF/printermap.sh" $printmap
# Make the printer mapping script executable
chmod +x "/Library/MSF/printermap.sh"

# URL of the print Launch Agent
printlunch="https://raw.githubusercontent.com/MSF-OCB/intune/main/MAC/printer_map.sh"
# Download printer Launch Agent
curl -o "/Library/LaunchAgents/com.msfocb.printermap.plist" $printlunch

echo "$(date) | File downloaded to /Library/MSF/Printer"

launchctl load "/Library/LaunchAgents/com.msfocb.printermap.plist"
