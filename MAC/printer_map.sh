#!/bin/bash
#set -x
############################################################################################
##
## Script to map shared network printers from Windows Print Server
##
############################################################################################

## Created by X: omar_assaf
## 

# Define the printer details
PROTOCOL="smb:"
PRINTER_BW="Ricoh-BW"
PRINTER_Color="Ricoh-Color"
PRINTSERVER="PRINTSERVER"
logdir="/Library/Logs/Microsoft/IntuneScripts/PrinterMap"                # Directory for logs
log="$logdir/PrinterMapping.log"                                         # The location of the script log file

function startLog() {

    ###################################################
    ###################################################
    ##
    ##  start logging - Output to log file and STDOUT
    ##
    ###################################################
    ###################################################

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
echo "############################################################"
echo "# $(date) | Logging Updating lockscreen to [$log]"
echo "############################################################"
echo ""

# Check if the server is reachable
if ping -c 1 "$PRINTSERVER" &> /dev/null
then
    echo "# $(date) | Server is reachable. Proceeding with printer mapping."

    # Get the current user's Kerberos ticket
    USER_TICKET=$(klist | grep "Default principal" | awk '{print $3}')

    # Check if the BW printer is already installed
    if lpstat -p | grep -q "$PRINTER_BW"; then
        echo "# $(date) | Printer $PRINTER_BW is already installed."
    else
        # Install the printer using the SSO credentials
        lpadmin -p "$PRINTER_BW" -E -v "$PROTOCOL//$PRINTSERVER/$PRINTER_BW" -P "/Library/Printers/PPDs/Contents/Resources/RICOH MP 4055" -o auth-info-required=negotiate
        echo "# $(date) | Printer $PRINTER_BW has been installed."
        # Set the printer as the default printer
        lpoptions -d "$PRINTER_BW"
    fi

    # Check if the Color printer is already installed
    if lpstat -p | grep -q "$PRINTER_Color"; then
        echo "# $(date) | Printer $PRINTER_Color is already installed."
    else
        # Install the printer using the SSO credentials
        lpadmin -p "$PRINTER_Color" -E -v "$PROTOCOL//$PRINTSERVER/$PRINTER_Color" -P "/Library/Printers/PPDs/Contents/Resources/RICOH MP 4055" -o auth-info-required=negotiate
        echo "# $(date) | Printer $PRINTER_Color has been installed."
    fi
else
    echo "Server is not reachable. Exiting."
fi
exit 0
