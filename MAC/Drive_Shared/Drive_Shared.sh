#!/bin/bash
#set -x
############################################################################################
##
## Script to map shared network printers from Windows Print Server
##
############################################################################################

## Created by X: omar_assaf
## 

# Define generic variables
logdir="/Library/Logs/MSF/IntuneScripts/Drives"                         # Directory for logs
log="$logdir/DriveMapping.log"                                          # The location of the script log file

# Variables
SERVER="CASSIDY"
SHARE="DATA"
MOUNT_POINT="/Volumes/Data"
VOLUME_NAME="Data"

# Check if the server is reachable
if ping -c 1 "$SERVER" &> /dev/null
then
    echo "$(date) | Server is reachable. Proceeding with mount."

    # Create the mount point if it doesn't exist
    if [ ! -d "$MOUNT_POINT" ]; then
        mkdir "$MOUNT_POINT"
    fi

    # Mount the SMB share
    mount_smbfs "//$SERVER/$SHARE" "$MOUNT_POINT"

    # Create a symbolic link on the desktop
    ln -s "$MOUNT_POINT" ~/Desktop/"$VOLUME_NAME"
else
    echo "$(date) | Server is not reachable. Exiting."
fi
