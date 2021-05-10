#!/bin/sh
echo "Welcome to your PHYTEC Board with support"
echo "for the ESEC IoT Device Manager Platform"
echo "OnBoarding state:"
if [ $(/usr/bin/jq .awsclient < /mnt/config/aws/config/esec.config | grep start | wc -l) -eq 0 ]; then
    echo "NOT onboarded"
    echo "Please start the phytec-board-config tool at first"
else
    echo "successful onboarded"
fi
